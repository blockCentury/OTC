pragma solidity ^0.4.18;

// utility contract for safe computation
/**
  * The libName library does this and that...
  */
 library SafeMath {
    function safeAdd(uint256 x, uint256 y) internal pure returns(uint256 z) {
        z = x + y;
        require((z >= x) && (z >= y));
    }
    function safeSubtract(uint256 x, uint256 y) internal pure returns(uint256 z) {
        require(x >= y);
        z = x - y;
    }
    function safeMult(uint256 x, uint256 y) internal pure returns(uint256 z) {
        z = x * y;
        assert((x == 0)||(z/x == y));
    }
    function safeDiv(uint256 x, uint256 y) internal pure returns(uint256 z){
        require(y > 0);
        z= x / y;
    }
 }


/* helper contract for ownership control
There will be functions that can only be executed from token official
this contract helps identify those ones
*/
contract owned {
    address public owner;

        function owned() public{
            owner = msg.sender;
        }

        modifier onlyOwner {
            require(msg.sender == owner);
            _;
        }

        function transferOwnership(address newOwner) onlyOwner public{
            owner = newOwner;
        }
    }

/* helper contract for token-token interaction */
interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public; }
/* main definition for our token*/
contract OTCPresale is owned{
    //member variables
    uint64 public sellPrice;
    uint64 public buyPrice;
    string public name = "blocktogoCoin";
    string public symbol = "OTCPresale";
    uint8 public decimals = 3;
    uint256 public totalSupply = 2000000000;
    bool public available = true;
    // uint64 public purchaseLimit = 120000000;

    mapping (address => uint256) public balanceOf;
    mapping (address => mapping (address => uint256)) public allowance;
    mapping (address => uint256) public unlockDate;
    mapping (address => bool) public frozenAccount;
    mapping (address => uint) public rewardPercentageMap;

    /* This generates a public event on the blockchain that will notify clients */
    event LogTransfer(address indexed from, address indexed to, uint256 value);
    /* Notify users whose latest purchase exceeds the limit*/
    event exceedPurchaseLimit(address buyer, uint currentBalance, uint holdingLimit);
    /* Notify clients that the address has been locked*/
    event FrozenFunds(address target, bool frozen);
    /* Notify clients when there's not enough funds for transfering*/
    event NotEnoughFunds(address account, uint256 currentBalance, uint256 need);
    /* Notify the availability change of coin */
    event CoinAvailability(bool canBuyCoin);
    /*notify contract holders there is a coin mint event*/
    event TokenMinted(address target, uint mintedAmount);
    /* Initializes contract with initial supply tokens to the creator of the contract */
    function OTCPresale(
        uint64 tokenBuyPrice,
        uint64 tokenSellPrice
    )public { 
        balanceOf[msg.sender] = totalSupply*10**uint256(decimals);
        buyPrice = tokenBuyPrice;
        sellPrice = tokenSellPrice;
    }

    function setDecimalPoints(uint8 _decimalUnit) onlyOwner public{
        decimals = _decimalUnit;
    }

    function _transfer(address _from, address _to, uint _value) internal{
        require(_to != 0x0);
        require(balanceOf[_from] >= _value);
        require(balanceOf[_to]+_value > balanceOf[_to]);

        uint previousBalances = balanceOf[_from]+balanceOf[_to];
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        LogTransfer(_from, _to, _value);
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }

    /* Send coins */
    function transfer(address _to, uint256 _value) public {
        _transfer(msg.sender, _to, _value);
    }

    /* A contract attempts to get the coins */
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);
        require(!frozenAccount[_from]);
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }


    function approve(address _spender, uint256 _value) public returns (bool success){
        allowance[msg.sender][_spender] = _value;
        return true;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData) public
        returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    //control the availability of token in the sale
    function setAvailibility(bool _canBuy) onlyOwner public{
        available = _canBuy;
    }

    //this is for system administration 
    function lock(address _target) onlyOwner public{
        frozenAccount[_target] = true;
        FrozenFunds(_target, true);
    }
    

    //lock account as requested
    function lockAccount(address _target) internal {
        frozenAccount[_target] = true;
        FrozenFunds(_target, true);
    }
    /*token holders can optionally request lock their account to hold the tokens,
    lockup duration can be 6 months, 12 months, 24 months and 36 months*/
    function requestLock(uint how_many_months) public returns(bool _success){
        unlockDate[msg.sender] = SafeMath.safeAdd(now, how_many_months*1 minutes);
        if(how_many_months == 6){
            rewardPercentageMap[msg.sender] = 0;
        }else if(how_many_months == 12){
            rewardPercentageMap[msg.sender] = 7;
        }
        else if(how_many_months == 24){
            rewardPercentageMap[msg.sender] = 15;
        }
        else if(how_many_months == 36){
            rewardPercentageMap[msg.sender] = 20;
        }
        lockAccount(msg.sender);
        return true;
    }

    // helper function for unlocking account
    function unlockAccount(address _locked) internal {
        frozenAccount[_locked] = false;
        FrozenFunds(_locked, false);
    }
    // helper function for administration
    function unlock(address _locked) onlyOwner public{
        frozenAccount[_locked] = false;
        FrozenFunds(_locked, false);
    }
    //user can call this function to request reward for their lockup
    function requestReward() public returns(bool _success) {
        if(now < unlockDate[msg.sender]){
            revert();
        } 
        unlockAccount(msg.sender);
        issueReward(msg.sender);
        rewardPercentageMap[msg.sender] = 0;
        return true;
    }
    /*issue lockup reward to token holders, the rewardAmount depends on their balance and 
    how long they locked up */
    function issueReward(address _to) internal{
        uint rewardAmount = SafeMath.safeMult(balanceOf[_to], rewardPercentageMap[_to])/100;
        transferFrom(owner, _to, rewardAmount);
        LogTransfer(owner, _to, rewardAmount);
    }
    //mint tokens to some address
    function mintToken(address target, uint256 mintedAmount) onlyOwner public{
        balanceOf[target] = SafeMath.safeAdd(balanceOf[target], mintedAmount);
        totalSupply = SafeMath.safeAdd(totalSupply, mintedAmount);
        LogTransfer(0, this, mintedAmount);
        LogTransfer(this, target, mintedAmount);
        TokenMinted(target, mintedAmount);
    }
/*you can make the token's value be backed by ether (or other tokens) by 
creating a fund that automatically sells and buys them at market value*/
    function setPrices(uint64 newSellPrice, uint64 newBuyPrice) onlyOwner public{
        sellPrice = newSellPrice;
        buyPrice = newBuyPrice;
    }
// people can buy my shares and pay wei/eth
    function buy() payable public returns (uint amount) {
        CoinAvailability(available);
        if(!available){
            revert();
        } 
        uint shares = SafeMath.safeDiv(msg.value,buyPrice);

        // if(safeAdd(shares, balanceOf[msg.sender]) > purchaseLimit) {
        //     exceedPurchaseLimit(msg.sender, safeAdd(shares, balanceOf[msg.sender]),purchaseLimit);
        //     revert();
        // }
        // pendingWithdraw += msg.value;
        transferFrom(owner, msg.sender, shares);
        // balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender], shares);
        // // balanceOf[msg.sender] += shares;     // adds the amount to buyer's balance
        // balanceOf[owner] = safeSubtract(balanceOf[owner], shares);
        // balanceOf[this] -= shares;          // subtracts amount from seller's balance
        return shares;                
    }
// people can sell their shares and get wei.
    function sell(uint256 amount) public returns (uint revenue){
        // checks if the sender has enough to sell
        require(balanceOf[msg.sender] >= amount );
        require(!frozenAccount[msg.sender]);
        
        transferFrom(msg.sender, owner, amount);
        // balanceOf[owner] = safeAdd(balanceOf[owner],amount); // adds the amount to owner's balance
        // balanceOf[msg.sender] = safeSubtract(balanceOf[msg.sender], amount); 
        // subtracts the amount from seller's balance
        uint income = amount*sellPrice;               
        if (!msg.sender.send(income)) {        // sends ether to the seller. It's important
            revert();                              // to do this last to avoid recursion attacks
        } else {
            return income;            
        }               
    }
    // function for withdraw funds
    function withdraw() public onlyOwner{
        // owner.transfer(pendingWithdraw);
        owner.transfer(this.balance);
    }

    function destroy() onlyOwner public{ // so funds not locked in contract forever
        if (msg.sender == owner) { 
            selfdestruct(owner); // send funds to organizer
        }
    }

    /**
     * Do not allow direct deposits when the coin is not buyable.
     *
     * All crowdsale depositors must have read the legal agreement.
     * This is confirmed by having them signing the terms of service on the website.
     * The give their crowdsale Ethereum source address on the website.
     * Website signs this address using crowdsale private key (different from founders key).
     * buy() takes this signature as input and rejects all deposits that do not have
     * signature you receive after reading terms of service.
     *
     */
    function() payable public {
        CoinAvailability(available);
        require(available);
        uint shares = SafeMath.safeDiv(msg.value, buyPrice);
        transferFrom(owner, msg.sender, shares);
        // pendingWithdraw += msg.value;

        // if(safeAdd(shares, balanceOf[msg.sender]) > purchaseLimit) {
        //     exceedPurchaseLimit(msg.sender, safeAdd(shares, balanceOf[msg.sender]),purchaseLimit);
        //     revert();
        // }
    }
}