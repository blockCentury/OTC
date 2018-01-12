pragma solidity ^0.4.10;

contract Token {
    uint256 public totalSupply;
    function balanceOf(address _owner) constant returns (uint256 balance);
    function transfer(address _to, uint256 _value) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) internal returns (bool success);
    function approve(address _spender, uint256 _value) returns (bool success);
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);
    event LogTransfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}


/*  ERC 20 token */
contract StandardToken is Token {

    function transfer(address _to, uint256 _value) returns (bool success) {
      if (balances[msg.sender] >= _value && _value > 0) {
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        LogTransfer(msg.sender, _to, _value);
        return true;
      } else {
        return false;
      }
    }

    function transferFrom(address _from, address _to, uint256 _value) internal returns (bool success) {
      if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
        balances[_to] += _value;
        balances[_from] -= _value;
        allowed[_from][msg.sender] -= _value;
        LogTransfer(_from, _to, _value);
        return true;
      } else {
        return false;
      }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }

    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
}

// utility contract for safe computation
contract SafeMath {

    function safeAdd(uint256 x, uint256 y) internal returns(uint256) {
      uint256 z = x + y;
      assert((z >= x) && (z >= y));
      return z;
    }

    function safeSubtract(uint256 x, uint256 y) internal returns(uint256) {
      assert(x >= y);
      uint256 z = x - y;
      return z;
    }

    function safeMult(uint256 x, uint256 y) internal returns(uint256) {
      uint256 z = x * y;
      assert((x == 0)||(z/x == y));
      return z;
    }

}

/* helper contract for ownership control
There will be functions that can only be executed from token official
this contract helps identify those ones
*/
contract owned {
    address public owner;

    function owned() {
        owner = msg.sender;
    }

    modifier onlyOwner {
        if (msg.sender != owner) revert();
        _;
    }

    function transferOwnership(address newOwner) onlyOwner {
        owner = newOwner;
    }
}

/* helper contract for token-token interaction */
contract tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData); }

/* main definition for our token*/
contract VVToken is owned, StandardToken, SafeMath {
    //member variables
    uint64 public sellPrice;
    uint64 public buyPrice;
    string public standard = 'Token 0.1';
    string public name = "VVToken";
    string public symbol = "CDT";
    uint8 public decimals = 1;
    uint256 public initialSupply = 24000000000;
    bool public available = true;
    uint64 public purchaseLimit = 120000000;
    uint private pendingWithdraw;

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
    function VVToken(
        uint64 tokenBuyPrice,
        uint64 tokenSellPrice
    ) { 
        balanceOf[msg.sender] = initialSupply;
        totalSupply = initialSupply;
        owner = msg.sender;
        buyPrice = tokenBuyPrice;
        sellPrice = tokenSellPrice;
    }

    function setDecimalPoints(uint8 _decimalUnit) onlyOwner{
        decimals = _decimalUnit;
    }

    /* Approve and then communicate the approved contract in a single tx */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData)
        returns (bool success) {
        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, this, _extraData);
            return true;
        }
    }

    /* Send coins */
    function transfer(address _to, uint256 _value) returns (bool success){
        transferFrom(msg.sender, _to, _value);            
        return true;
    }


    /* A contract attempts to get the coins */
    function transferFrom(address _from, address _to, uint256 _value) internal returns (bool success) {
        // Check if frozen
        if (frozenAccount[_from]){
            revert();
        } 
        // Check if the sender has enough
        if (balanceOf[_from] < _value){
            NotEnoughFunds(_from, balanceOf[_from], _value);
            revert();
        }
        // Check for overflows                  
        if (safeAdd(balanceOf[_to], _value) < balanceOf[_to]) revert();  
        // Subtract from the sender
        balanceOf[_from] = safeSubtract(balanceOf[_from], _value);                          
        // Add the same to the recipient
        balanceOf[_to] = safeAdd(balanceOf[_to], _value);                             
        // allowance[_from][msg.sender] -= _value;
        // Notify anyone listening that this transfer took place
        LogTransfer(_from, _to, _value);
        return true;
    }

    //control the availability of token in the sale
    function setAvailibility(bool _canBuy) onlyOwner{
        available = _canBuy;
    }

    //lock account as requested
    function lockAccount(address _target) internal {
        frozenAccount[_target] = true;
        FrozenFunds(_target, true);
    }

    //this is for system administration 
    function lock(address _target) onlyOwner {
        frozenAccount[_target] = true;
        FrozenFunds(_target, true);
    }
    
    /*token holders can optionally request lock their account to hold the tokens,
    lockup duration can be 6 months, 12 months, 24 months and 36 months*/
    function requestLock(uint how_many_months) returns(bool _success){
        unlockDate[msg.sender] = safeAdd(now, how_many_months*1 minutes);
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
    function unlock(address _locked) onlyOwner {
        frozenAccount[_locked] = false;
        FrozenFunds(_locked, false);
    }
    //user can call this function to request reward for their lockup
    function requestReward() returns(bool _success){
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
        uint rewardAmount = safeMult(balanceOf[_to], rewardPercentageMap[_to])/100;
        transferFrom(owner, _to, rewardAmount);
        LogTransfer(owner, _to, rewardAmount);
    }
    //mint tokens to some address
    function mintToken(address target, uint256 mintedAmount) onlyOwner {
        balanceOf[target] = safeAdd(balanceOf[target], mintedAmount);
        totalSupply = safeAdd(totalSupply, mintedAmount);
        LogTransfer(0, this, mintedAmount);
        LogTransfer(this, target, mintedAmount);
        TokenMinted(target, mintedAmount);
    }
/*you can make the token's value be backed by ether (or other tokens) by 
creating a fund that automatically sells and buys them at market value*/
    function setPrices(uint64 newSellPrice, uint64 newBuyPrice) onlyOwner {
        sellPrice = newSellPrice;
        buyPrice = newBuyPrice;
    }
// people can buy my shares and pay wei/eth
    function buy() payable returns (uint amount){
        CoinAvailability(available);
        if(!available){
            revert();
        } 
        uint shares = msg.value / buyPrice;

        if(safeAdd(shares, balanceOf[msg.sender]) > purchaseLimit) {
            exceedPurchaseLimit(msg.sender, safeAdd(shares, balanceOf[msg.sender]),purchaseLimit);
            revert();
        }
        pendingWithdraw += msg.value;
        balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender], shares);
        // balanceOf[msg.sender] += shares;     // adds the amount to buyer's balance
        balanceOf[owner] = safeSubtract(balanceOf[owner], shares);
        // balanceOf[this] -= shares;          // subtracts amount from seller's balance
        LogTransfer(owner, msg.sender, shares);// execute an event reflecting the change
        return shares;                
    }
// people can sell their shares and get wei.
    function sell(uint256 amount) returns (uint revenue){
        // checks if the sender has enough to sell
        if (balanceOf[msg.sender] < amount ){
            revert();
        }  
        if (frozenAccount[msg.sender]){
            revert();
        } 
      
        balanceOf[owner] = safeAdd(balanceOf[owner],amount); // adds the amount to owner's balance
        balanceOf[msg.sender] = safeSubtract(balanceOf[msg.sender], amount); 
        // subtracts the amount from seller's balance
        uint income = amount*sellPrice;               
        if (!msg.sender.send(income)) {        // sends ether to the seller. It's important
            revert();                              // to do this last to avoid recursion attacks
        } else {
            LogTransfer(msg.sender, owner, amount); // executes an event reflecting on the change
            return income;            
        }               
    }
    // function for withdraw funds
    function withdraw() onlyOwner{
        owner.transfer(pendingWithdraw);
        pendingWithdraw = 0;
    }

    function destroy() onlyOwner{ // so funds not locked in contract forever
        if (msg.sender == owner) { 
            suicide(owner); // send funds to organizer
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
    function() payable {
        CoinAvailability(available);
        if(!available){
            revert();
        }
        // require(available); 
        uint shares = msg.value / buyPrice;

        pendingWithdraw += msg.value;

        if(safeAdd(shares, balanceOf[msg.sender]) > purchaseLimit) {
            exceedPurchaseLimit(msg.sender, safeAdd(shares, balanceOf[msg.sender]),purchaseLimit);
            revert();
        }
        // adds the amount to buyer's balance
        balanceOf[msg.sender] = safeAdd(balanceOf[msg.sender], shares);
        // subtracts amount from seller's balance
        balanceOf[owner] = safeSubtract(balanceOf[owner], shares);
        // execute an event reflecting the change  
        LogTransfer(owner, msg.sender, shares);
    }
}