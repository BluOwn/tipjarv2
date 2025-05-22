// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TipJarOptimized
 * @dev Size-optimized upgradeable tip jar contract
 * @notice Reduced feature set to stay under contract size limit
 */
contract TipJarOptimized is 
    Initializable, 
    ReentrancyGuardUpgradeable, 
    OwnableUpgradeable, 
    PausableUpgradeable,
    UUPSUpgradeable 
{
    // Constants
    uint256 public constant PLATFORM_FEE_BASIS_POINTS = 100; 
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10000;
    uint256 public constant MIN_TIP_AMOUNT = 10000000000000000; // 0.01 ETH
    uint256 public constant MAX_USERNAME_LENGTH = 32;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 256;
    uint256 public constant MAX_MESSAGE_LENGTH = 280;
    
    // State variables
    address public feeRecipient;
    
    struct Tip {
        address sender;
        uint256 amount;
        string message;
        uint256 timestamp;
    }

    struct JarInfo {
        address owner;
        string description;
        uint256 totalReceived;
        bool exists;
    }
    
    // Core mappings
    mapping(string => JarInfo) public jars;
    mapping(address => string) public ownerToUsername;
    mapping(string => Tip[]) public tipHistory;
    mapping(address => uint256) public failedTipAmounts;
    string[] public allUsernames;
    mapping(string => bool) private _normalizedUsernameExists;
    
    // Events
    event JarCreated(address indexed owner, string username);
    event JarDeleted(address indexed owner, string username);
    event JarDeletedByAdmin(address indexed admin, address indexed owner, string username);
    event TipSent(address indexed sender, string indexed toUsername, uint256 totalAmount, string message, uint256 tipAmount, uint256 fee);
    event TipFailed(address indexed recipient, uint256 amount);
    event FailedTipWithdrawn(address indexed recipient, uint256 amount);
    event FeePaid(address indexed recipient, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        feeRecipient = msg.sender;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    modifier usernameAvailable(string memory username) {
        require(!jars[username].exists, "Username taken");
        string memory norm = _toLower(username);
        require(!_normalizedUsernameExists[norm], "Username taken (case)");
        _;
    }

    modifier jarExists(string memory username) {
        require(jars[username].exists, "Jar not exist");
        _;
    }

    modifier validUsername(string memory username) {
        require(bytes(username).length > 0 && bytes(username).length <= MAX_USERNAME_LENGTH, "Invalid length");
        require(_isValidUsername(username), "Invalid chars");
        _;
    }

    function _isValidUsername(string memory str) internal pure returns (bool) {
        bytes memory b = bytes(str);
        for (uint i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (!(c >= 0x30 && c <= 0x39) && !(c >= 0x41 && c <= 0x5A) && 
                !(c >= 0x61 && c <= 0x7A) && !(c == 0x5F) && !(c == 0x2D) && !(c == 0x2E)) {
                return false;
            }
        }
        return true;
    }

    function createJar(string memory username, string memory description) 
        public 
        whenNotPaused
        usernameAvailable(username)
        validUsername(username)
    {
        require(bytes(ownerToUsername[msg.sender]).length == 0, "Already have jar");
        require(bytes(description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        
        jars[username] = JarInfo({
            owner: msg.sender,
            description: description,
            totalReceived: 0,
            exists: true
        });
        
        _normalizedUsernameExists[_toLower(username)] = true;
        ownerToUsername[msg.sender] = username;
        allUsernames.push(username);
        
        emit JarCreated(msg.sender, username);
    }

    function deleteJar() public {
        string memory username = ownerToUsername[msg.sender];
        require(bytes(username).length > 0, "No jar");
        _performJarDeletion(msg.sender, username);
        emit JarDeleted(msg.sender, username);
    }

    function adminDeleteJar(string memory username) public onlyOwner jarExists(username) {
        address jarOwner = jars[username].owner;
        _performJarDeletion(jarOwner, username);
        emit JarDeletedByAdmin(msg.sender, jarOwner, username);
    }

    function adminDeleteJarByOwner(address jarOwner) public onlyOwner {
        string memory username = ownerToUsername[jarOwner];
        require(bytes(username).length > 0, "No jar");
        _performJarDeletion(jarOwner, username);
        emit JarDeletedByAdmin(msg.sender, jarOwner, username);
    }

    function _performJarDeletion(address jarOwner, string memory username) internal {
        delete ownerToUsername[jarOwner];
        delete _normalizedUsernameExists[_toLower(username)];
        delete jars[username];
        
        // Remove from allUsernames
        for (uint256 i = 0; i < allUsernames.length; i++) {
            if (keccak256(bytes(allUsernames[i])) == keccak256(bytes(username))) {
                allUsernames[i] = allUsernames[allUsernames.length - 1];
                allUsernames.pop();
                break;
            }
        }
    }

    function sendTip(string memory username, string memory message) 
        public 
        payable 
        whenNotPaused
        jarExists(username)
        nonReentrant 
    {
        require(msg.value >= MIN_TIP_AMOUNT, "Too small");
        require(bytes(message).length <= MAX_MESSAGE_LENGTH, "Message too long");
        
        uint256 fee = (msg.value * PLATFORM_FEE_BASIS_POINTS) / BASIS_POINTS_DENOMINATOR;
        uint256 tipAmount = msg.value - fee;
        
        jars[username].totalReceived += tipAmount;
        
        tipHistory[username].push(Tip({
            sender: msg.sender,
            amount: msg.value,
            message: message,
            timestamp: block.timestamp
        }));
        
        // Send fee
        if (fee > 0) {
            (bool feeSuccess, ) = feeRecipient.call{value: fee}("");
            if (!feeSuccess) {
                failedTipAmounts[feeRecipient] += fee;
                emit TipFailed(feeRecipient, fee);
            }
            emit FeePaid(feeRecipient, fee);
        }
        
        // Send tip
        (bool tipSuccess, ) = jars[username].owner.call{value: tipAmount}("");
        if (!tipSuccess) {
            failedTipAmounts[jars[username].owner] += tipAmount;
            emit TipFailed(jars[username].owner, tipAmount);
        }
        
        emit TipSent(msg.sender, username, msg.value, message, tipAmount, fee);
    }

    function withdrawFailedTips() public nonReentrant {
        uint256 amount = failedTipAmounts[msg.sender];
        require(amount > 0, "No failed tips");
        
        failedTipAmounts[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit FailedTipWithdrawn(msg.sender, amount);
    }

    // View functions
    function getJarInfo(string memory username) 
        public 
        view 
        jarExists(username) 
        returns (address owner, string memory description, uint256 totalReceived) 
    {
        JarInfo storage jar = jars[username];
        return (jar.owner, jar.description, jar.totalReceived);
    }

    function getTipCount(string memory username) 
        public 
        view 
        jarExists(username) 
        returns (uint256) 
    {
        return tipHistory[username].length;
    }

    function getRecentTips(string memory username) 
        public 
        view 
        jarExists(username) 
        returns (address[] memory, uint256[] memory, string[] memory, uint256[] memory) 
    {
        uint256 length = tipHistory[username].length;
        if (length == 0) {
            return (new address[](0), new uint256[](0), new string[](0), new uint256[](0));
        }
        
        uint256 resultLength = length > 10 ? 10 : length;
        address[] memory senders = new address[](resultLength);
        uint256[] memory amounts = new uint256[](resultLength);
        string[] memory messages = new string[](resultLength);
        uint256[] memory timestamps = new uint256[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            uint256 index = length - resultLength + i;
            senders[i] = tipHistory[username][index].sender;
            amounts[i] = tipHistory[username][index].amount;
            messages[i] = tipHistory[username][index].message;
            timestamps[i] = tipHistory[username][index].timestamp;
        }
        
        return (senders, amounts, messages, timestamps);
    }

    function hasJar(address user) public view returns (bool) {
        return bytes(ownerToUsername[user]).length > 0;
    }

    function getUserJar(address user) public view returns (string memory) {
        require(bytes(ownerToUsername[user]).length > 0, "No jar");
        return ownerToUsername[user];
    }

    function isUsernameAvailable(string memory username) public view returns (bool) {
        if (jars[username].exists) return false;
        return !_normalizedUsernameExists[_toLower(username)];
    }

    // Admin functions
    function setFeeRecipient(address newFeeRecipient) public onlyOwner {
        require(newFeeRecipient != address(0), "Invalid address");
        feeRecipient = newFeeRecipient;
    }

    function pause() public onlyOwner { _pause(); }
    function unpause() public onlyOwner { _unpause(); }

    function websiteURL() public pure returns (string memory) {
        return "https://montip.xyz/";
    }

    function getVersion() public pure returns (string memory) {
        return "v1.0.0-optimized";
    }
    
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        
        for (uint i = 0; i < bStr.length; i++) {
            if (bStr[i] >= 0x41 && bStr[i] <= 0x5A) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        
        return string(bLower);
    }
}