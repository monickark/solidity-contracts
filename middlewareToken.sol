pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MiddleWare{
                                    //contractaddress: 0x232736A7D9A223106F2Cc7Ab72db6396b3fF744f
    address payable private admin; //0xC0740FA239ba988e8bEE841834877cE1fb83a268
    address private owner;        // 0x4a0faC30D46c0652a4E08110a92225d0173d169A
    ERC20 private token;         // 0x951Ae1103B5Ca4459ECCBd378eF4a86211c06052
    
    modifier onlyOwner {
        require(msg.sender == owner, "Sender not Owner.");
        _;
    }
    
    constructor(address payable _admin, ERC20 _token, address _token_owner){
        owner = msg.sender;
        admin = _admin;
        token = _token;
    }
    
    event Deposit(address indexed from, uint indexed id, uint indexed _value);

    fallback() external{  }
     
    function currentOwner() public view virtual returns (address) {
        return owner;
    }
    
    function currentAdmin() public view virtual returns (address) {
        return admin;
    }
    
    function transferOwnership(address _newOwner)onlyOwner external returns(bool) {
        owner = _newOwner;
        return true;
    }
    
    function updateAdmin(address payable _newAdmin)onlyOwner external returns(bool){
        admin = _newAdmin;
        return true;
    }
    
    function deposit(uint256 _id, uint256 amount) external returns (bool) {
        require(amount > 0, "Value needs to be not 0");
        token.transferFrom(msg.sender, admin, amount);
        emit Deposit(msg.sender, _id, amount);
        return true;
    }
}
