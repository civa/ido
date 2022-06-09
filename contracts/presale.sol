// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;


abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}



contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }   
    
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }


    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

}


abstract contract ReentrancyGuard {
   
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

   
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function stakes(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns(uint8);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

}



contract IDO is ReentrancyGuard, Context, Ownable {

    mapping (address => uint256) public _contributions;
    mapping (address => bool) public _whitelisted;
    
    IERC20 public _token;
    uint256 private _tokenDecimals;
    address public _wallet;
    IERC20 public _stakeContract;
    uint256 public _rate;
    uint256 public _weiRaised;
    uint256 public endIDO;
    uint public minPurchase;
    uint public maxPurchase;
    uint public minimumStake;
    uint public hardcap;
    uint public purchasedTokens;
    bool public unlock;
    bool public allowNonWhitelist = false;
    uint public whitelistCap;



    
    address[] private whitelistAddresses;

    event TokensPurchased(address  purchaser, uint256 value, uint256 amount);
    event Refund(address recipient, uint256 amount);
    constructor (uint256 rate, uint256 minStake, uint256 _whitelistcap , address wallet, IERC20 stakeContract, IERC20 token)  {
        require(rate > 0, "Pre-Sale: rate is 0");
        require(wallet != address(0), "Pre-Sale: wallet is the zero address");
        require(address(token) != address(0), "Pre-Sale: token is the zero address");
        
        _rate = rate;
        _stakeContract = stakeContract;
        minimumStake = minStake;
        _wallet = wallet;
        whitelistCap = _whitelistcap;
        
        _token = token;
        _tokenDecimals = 18 - _token.decimals();
    }
    
    function setWhitelist(address[] memory recipients) public onlyOwner{
        for(uint256 i = 0; i < recipients.length; i++){
            _whitelisted[recipients[i]] = true;
        }
        whitelistAddresses = recipients;
    }
    
    function whitelistAccount(address account, bool value) external onlyOwner{
        _whitelisted[account] = value;
    }
    
    
    //Start Pre-Sale
    function startIDO(uint endDate, uint _minPurchase, uint _maxPurchase, uint256 _hardcap) external onlyOwner idoNotActive() {
        require(whitelistAddresses.length > 0, 'Whitelist not set yet');
        require(endDate > block.timestamp, 'duration should be > 0');
        require(_minPurchase > 0, '_minPurchase should > 0');
        endIDO = endDate; 
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
        hardcap = _hardcap;
        _weiRaised = 0;
    }
    
    function stopIDO() external onlyOwner idoActive(){
        endIDO = 0;
    }
    
    //Pre-Sale 
    function buyTokens() public nonReentrant idoActive payable{
        IERC20 tokenBEP = _stakeContract;
        require (tokenBEP.stakes(msg.sender) >= minimumStake, "You need to stake more than minimum AVN amount");
        uint256 weiAmount = msg.value;
        uint256 tokens = _getTokenAmount(weiAmount);
        _preValidatePurchase(msg.sender, weiAmount);
        _weiRaised = _weiRaised + weiAmount;
        purchasedTokens += tokens;
        _contributions[msg.sender] = _contributions[msg.sender] + weiAmount;
        emit TokensPurchased(msg.sender, weiAmount, tokens);
    }

    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view {
        require(beneficiary != address(0), "Presale: beneficiary is the zero address");
        if (allowNonWhitelist == false) {
        require(_whitelisted[beneficiary], "You are not in whitelist");
        }
        require(weiAmount != 0, "Presale: weiAmount is 0");
        require(weiAmount >= minPurchase, 'have to send at least: minPurchase');
        require(_weiRaised + weiAmount <= hardcap, "Exceeding hardcap");
        if (_whitelisted[beneficiary] == true){
             require(_contributions[beneficiary] + weiAmount <= whitelistCap, "can't buy more than: whitelistCap");
        } else {
            require(_contributions[beneficiary] + weiAmount <= maxPurchase, "can't buy more than: maxPurchase");
        }
    }
    function returnStakeAmount(address _address) public view returns(uint){
        uint stakeAmount;
        IERC20 tokenBEP = _stakeContract;
        stakeAmount = tokenBEP.stakes(_address);
        return stakeAmount;
    }

    function checkWhitelist(address account) external view returns(bool){
        return _whitelisted[account];
    }

    function _getTokenAmount(uint256 weiAmount) internal view returns (uint256) {
        return weiAmount * _rate / 10**_tokenDecimals;
    }

    function _forwardFunds(uint256 amount) external onlyOwner {
        payable(_wallet).transfer(amount);
    }
    function _setMinStake(uint256 _newAmount) public onlyOwner {
    minimumStake = _newAmount;
    }
    function setNewRate(uint256 _newRate) public onlyOwner {
        _rate = _newRate;
    }
    function setWhitelistCap(uint256 _newCap) public onlyOwner {
        whitelistCap = _newCap;
    }
    function startIdoRound2(bool _trueorfalse) public onlyOwner{
        require(_weiRaised <= hardcap);
        allowNonWhitelist = _trueorfalse;
    }
    
    function checkContribution(address addr) public view returns(uint256){
        uint256 tokensBought = _getTokenAmount(_contributions[addr]);
        return (tokensBought);
    }
    
    function setWalletReceiver(address newWallet) external onlyOwner(){
        _wallet = newWallet;
    }
    
    function setMaxPurchase(uint256 value) external onlyOwner{
        maxPurchase = value;
    }
    
     function setMinPurchase(uint256 value) external onlyOwner{
        minPurchase = value;
    }
    
    function setHardcap(uint256 value) external onlyOwner{
        hardcap = value;
    }
    
    function takeUnsoldTokens(IERC20 tokenAddress) public onlyOwner{
        IERC20 tokenBEP = tokenAddress;
        uint256 tokenAmt = tokenBEP.balanceOf(address(this));
        require(tokenAmt > 0, 'BEP-20 balance is 0');
        tokenBEP.transfer(_wallet, tokenAmt);
    }
    
    modifier idoActive() {
        require(endIDO > 0 && block.timestamp < endIDO && _weiRaised < hardcap, "IDO must be active");
        _;
    }
    
    modifier idoNotActive() {
        require(endIDO < block.timestamp, 'IDO should not be active');
        _;
    }
    function withdrawTokens() public {
        require(unlock == true);
         IERC20 tokenBEP = _token;
          tokenBEP.transfer(msg.sender, (checkContribution(msg.sender)));
         _contributions[msg.sender] = 0;
    }
    function addContribution(address _address, uint256 _bnbAmount) public onlyOwner{
        uint256 bnbAmount = _bnbAmount ;
        _contributions[_address] = _contributions[_address] + bnbAmount;
 
    }    
    function subContribution(address _address, uint256 _bnbAmount) public onlyOwner{
        uint256 bnbAmount = _bnbAmount ;
        _contributions[_address] = _contributions[_address] - bnbAmount;
 
    } 
    function unlockToken(bool _input) public {
        unlock = _input;
    }
}
