// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MetaNFTAuction is Initializable, IERC721Receiver{
    address private admin;
    bool public isTestMode; // 测试模式开关：true=使用Mock，false=使用真实预言机
    mapping(uint256 => address) public priceFeedAddresses; // 支付方式 => 预言机地址（1=ETH，2=USDC

    struct Auction {
        address seller;                 // 卖家地址
        IERC721 nft;                    // nft合约
        uint256 nftId;                  // NFT的tokenId

        bool end;                       // 拍卖是否结束 true->结束 ｜ false->未结束
        uint256 startTime;              // 拍卖开始时间
        uint256 duration;               // 拍卖持续时间
        address highestBidder;          // 最高出价者地址
        uint256 highestBid;             // 最高出价
        IERC20 paymentToken;            // ERC20代币
        uint256 highestBidInDollar;     // 最高出价（美元计算）
        uint256 startingPriceInDollar;  // 起拍价（美元计算）
    }

    // 拍卖合约 [ID号][竞拍者地址] => 竞拍过程中累计锁定在合约中的金额(ETH 或 USDC) 的映射，用于核算退款
    mapping(uint256 => mapping(address => uint256)) bids;
    // 拍卖合约 [ID号][竞拍者地址] => 当前拍卖合约的出价方式 的映射 0:第一次出价 1:ETH 2:USDC
    mapping(uint256 => mapping(address => uint256)) bidMethods;
    mapping(uint256 => Auction) public auctions;
    uint256 public auctionId;

    constructor(){
        _disableInitializers();
    }

    function initialize(
        address admin_,
        bool _isTestMode, // 新增：测试模式开关
        address _ethPriceFeed, // 新增：ETH预言机地址（Mock/真实）
        address _usdcPriceFeed // 新增：USDC预言机地址（Mock/真实）
    ) public initializer {
        require(admin_ != address(0), "admin is address 0");
        admin = admin_;
        isTestMode = _isTestMode;
    
        // 配置预言机地址
        priceFeedAddresses[1] = _ethPriceFeed; // ETH/USD 预言机地址
        priceFeedAddresses[2] = _usdcPriceFeed; // USDC/USD 预言机地址
    }

    modifier onlyAdmin(){
        require(admin == msg.sender, "Not Admin!");
        _;
    }
    // ID为auctionId_ 的拍卖 「已结束」
    modifier auctionEnded(uint256 auctionId_){
        require(auctions[auctionId_].end, "Auction not end!");
        _;
    }
    // ID为auctionId_ 的拍卖 「未结束」
    modifier auctionNotEnded(uint256 auctionId_){
        require(!auctions[auctionId_].end, "Auction end!");
        _;
    }

    // 创建拍卖事件
    event StartBid(uint256 auctionId);
    // 竞拍事件
    event Bid(uint256 indexed auctionId, uint256 indexed amount, uint256 bidMethod);
    // 竞拍失败者退款事件
    event Withdraw(uint256 indexed auctionId, address indexed bidder, uint256 bal);
    // 竞拍成功事件
    event BidFinally(uint256 indexed auctionId, address indexed seller, address indexed bidder, uint256 bid);

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override returns(bytes4){
        return IERC721Receiver.onERC721Received.selector;
    }

    // 开始拍卖
    function startBid(
        address _seller,
        address _nft,
        uint256 _nftId,
        uint256 _duration,
        address _paymentToken,
        uint256 _startingPriceInDollar
    ) public onlyAdmin {
        // 校验NFT卖家是否持有该NFT
        require(IERC721(_nft).ownerOf(_nftId) == _seller, "Seller is not NFT owner");

        // admin 新建拍卖ID为 auctionId 的拍卖
        auctions[auctionId] = Auction({
            seller : _seller,
            nft: IERC721(_nft),
            nftId: _nftId,
            end: false,
            startTime: block.timestamp,
            duration:_duration,
            highestBidder:address(0),
            highestBid: 0,
            paymentToken: IERC20(_paymentToken),
            highestBidInDollar:0,
            startingPriceInDollar: _startingPriceInDollar
        });
        emit StartBid(auctionId);

        // NFT持有者将NFT转给当前合约
        IERC721(_nft).safeTransferFrom(_seller, address(this), _nftId);
        
        auctionId++;
    }

    // 买家竞拍(竞拍必须未结束)
    // 竞拍需要支付ETH或Token锁定在合约中
    // 竞拍成功获取NFT，退还竞拍过程中质押的多余金额
    // 竞拍失败退还全部质押金额
    function bid(uint256 _auctionId, uint256 _erc20Amount) external payable auctionNotEnded(_auctionId){
        Auction storage auction = auctions[_auctionId];
        uint256 allowance = auction.paymentToken.allowance(msg.sender, address(this));


        // 判断拍卖是否 随着时间 自然截止
        require(block.timestamp < auction.startTime + auction.duration, "auction is end!");
        // 判断出价金额 无论是 ETH 还是 USDC 必须大于 0
        require(msg.value > 0 || _erc20Amount > 0, "invalid bid");
        require((msg.value > 0) != (_erc20Amount > 0), "invalid method");
        
        // 本次竞拍出价对应的美元价格
        uint256 bidPrice;
        // 竞拍者 在 本次竞拍的出价方式：0:第一次竞价 1:ETH 2:USDC
        uint256 bidMethod;
        uint256 bidAmount;

        if(msg.value > 0){
            require(_erc20Amount == 0, "ETH bid: erc20Amount must be 0");
            bidMethod = bidMethods[_auctionId][msg.sender];
            // 说明 竞拍者出价方式为 ETH
            if (bidMethod == 0){
                // 此竞拍者 是第一次竞价
                bidMethod = 1; 
                bidAmount = msg.value;
                bidMethods[_auctionId][msg.sender] = bidMethod;
            } else {
                // 这里检查 竞拍者 本次出价方式 = 之前的竞拍方式
                require(bidMethod == 1, "invalid method");
                bidAmount = msg.value;
            }

            // 调用预言机获取当前美元汇率（单价）
            uint256 dollarPrice = getPriceInDollar(bidMethod);
            bidPrice = _toUsd(msg.value, 18, dollarPrice);
            
            // 当前竞拍最高出价为 msg.value 个 ETH
            auction.highestBid = msg.value;

            // 当前竞拍人的出价金额锁定在合约中 累加所有金额
            // 若竞拍成功，需要退还（累计金额-最高出价金额=竞拍过程中不断质押的金额）
            // 若竞拍失败，需要退还所有累加金额
            bids[_auctionId][msg.sender] += msg.value;
            emit Bid(_auctionId, msg.value, bidMethod);
        } else {
            require(_erc20Amount > 0, "ERC20 bid: amount must > 0");
            bidMethod = bidMethods[_auctionId][msg.sender];
            // 支付方式为Token
            if (bidMethod == 0){
                bidMethod = 2;
                bidAmount = _erc20Amount;
                bidMethods[_auctionId][msg.sender] = bidMethod;
            } else {
                require(bidMethod == 2, "invalid method");
                bidAmount = _erc20Amount;
            }

            // 校验授权额度
            require(allowance >= bidAmount, "ERC20 allowance insufficient");

            uint256 price = getPriceInDollar(bidMethod);
            uint256 tokenDecimals = IERC20Metadata(address(auction.paymentToken)).decimals();
            bidPrice = _toUsd(bidAmount, tokenDecimals, price);

            // 当前拍卖最高出价为 bidAmount个USDC
            auction.highestBid = bidAmount;
            
            // 当前竞拍人的出价金额累加 
            // 若竞拍成功，需要退还（累计金额-最高出价金额）
            // 若竞拍失败，需要退还所有累加金额
            auction.paymentToken.transferFrom(msg.sender, address(this), bidAmount);
            bids[_auctionId][msg.sender] += bidAmount;
            emit Bid(_auctionId, bidAmount, bidMethod);
        }

        // 判断 竞拍出价的 美元价格 > 起拍价 美元价格
        require(bidPrice > auction.startingPriceInDollar, "invalid startingPrice");
        // 判断出价金额 换算成美元 必须大于当前最高竞拍 美元 价格
        require(bidPrice > auction.highestBidInDollar, "Your bid must be higher than the current highest bid");
        
        // 当前竞拍最高出价者为：msg.sender
        auction.highestBidder = msg.sender;

        // 当前最高出价 = bidPrice美元 的 Token
        auction.highestBidInDollar = bidPrice;
    }

    
    // 拍卖已经结束, 管理员调用此方法结算 卖家和买家的交易
    // 竞拍成功者：退还：（竞拍过程中锁定在合约中的钱 - 竞拍价格）并获得NFT
    // 竞拍失败者：退还所有竞拍过程中锁定在合约中的钱
    function bidFinally(uint256 _auctionId) external onlyAdmin {
        Auction storage auction = auctions[_auctionId];
        
        require(block.timestamp > auction.startTime + auction.duration, "Auction not end!");
        // 设置拍卖结束
        _setAuctionEnd(_auctionId);
        // 赢家 竞拍的方式（ETH或USDC）
        uint256 successBidderBidMethods = bidMethods[_auctionId][auction.highestBidder];
        // 赢家 锁定在合约中的所有 ETH/USDC 数额
        uint256 successBiddersAmount = bids[_auctionId][auction.highestBidder];
        // 需要返还给竞拍成功者的 ETH/USDC 数额（竞拍过程中锁定在合约中的钱 - 竞拍成交的钱)
        uint256 rebackAmount = successBiddersAmount - auction.highestBid;
        // 先更新状态，再转账
        bids[_auctionId][auction.highestBidder] = 0;

        // 将 seller 锁定在本合约中的 NFT 转移给赢家
        auction.nft.safeTransferFrom(address(this), auction.highestBidder,auction.nftId);
        
        // 判断赢家的竞拍 付款方式
        if(successBidderBidMethods == 1){
            // ETH
            (bool success,) = auction.highestBidder.call{value:rebackAmount}("");
            require(success, "reback amount error");

            // 将成交额转给NFT持有者：seller
            (bool success2,) = auction.seller.call{value: auction.highestBid}("");
            require(success2, "Invalid transfer");
            
        }else{
            // USDC
            require(
                auction.paymentToken.allowance(address(this), auction.highestBidder) >= rebackAmount,
                "Insufficient allowance"
            );
            // 将竞拍过程中产生的额外费用转回给赢家
            auction.paymentToken.transferFrom(address(this), auction.highestBidder, rebackAmount);
            // 将成交额转给NFT持有者
            auction.paymentToken.transferFrom(address(this), auction.seller, auction.highestBid);

        }

        // 触发拍卖成功事件
        emit BidFinally(_auctionId, auction.seller, auction.highestBidder, auction.highestBid);
    }

    // 竞拍失败者 调用withdraw函数退款，拍卖必须结束
    function withdraw(uint256 auctionId_) external auctionEnded(auctionId_) returns(uint256) {
        Auction storage auction = auctions[auctionId_];

        uint256 bidMethod = bidMethods[auctionId_][msg.sender];
        uint256 bal = bids[auctionId_][msg.sender];
        require(bal > 0, "Invalid withdraw");

        bids[auctionId_][msg.sender] = 0;
        if (bidMethod == 1) {
            payable(msg.sender).transfer(bal);
        } else {
            // 这里使用transfer方法 合约从自己的地址转给msg.sender
            IERC20(address(auction.paymentToken)).transfer(msg.sender, bal);
        }
        // 触发失败者退款事件
        emit Withdraw(auctionId, msg.sender, bal);
        return bal;
    }

    // admin 手动设置拍卖结束
    function _setAuctionEnd(uint256 auctionId_) internal onlyAdmin auctionNotEnded(auctionId_) {
        Auction storage auction = auctions[auctionId_];
        auction.end = true;
    }

    // 预言机
    function getPriceInDollar(uint256 bidMethod) public view returns(uint256) {
        require(bidMethod == 1 || bidMethod == 2, "Invalid bid method");
    
        // 核心：根据测试模式/生产模式选择预言机地址
        address feedAddress = priceFeedAddresses[bidMethod];
        AggregatorV3Interface dataFeed = AggregatorV3Interface(feedAddress);

        // 调用预言机（Mock/真实都兼容，因为Mock实现了相同接口）
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = dataFeed.latestRoundData();

        // 安全校验：确保价格有效
        require(answer > 0, "Invalid price feed answer");
        require(updatedAt > 0, "Price feed not updated");

        return uint256(answer);
    }

    // 根据数量、小数位数、美元汇率，计算美元价格
    function _toUsd(uint256 amount, uint256 amountDecimals, uint256 price) 
    internal 
    pure
    returns(uint256)
    {
        // 计算10的小数位数次方
        uint256 scale = 10 ** amountDecimals;
        // Chainlink预言机返回的价格带8位小数，需要除以10^8
        uint256 priceWithoutDecimals = price / 10 ** 8;
        // 美元价格 = 汇率 * 数量 / scale次方
        uint256 usd = (amount * priceWithoutDecimals) / scale;
        return usd;
    }
}