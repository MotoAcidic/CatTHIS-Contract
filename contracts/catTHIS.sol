// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/EnumerableSet.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";

contract catTHIS is ERC20("CatTHIS", "CATS"), AccessControl {
    using SafeMath for uint256;

    uint public _totalSupply = 21000000e18; //21m
    uint internal _contractPremine = 0; // 5000000e18; // 5m coins
    uint internal _minStakeamount = 10000; // 10k coins in order to be added to the staking list
    
    // Reward based variables
    uint256 internal _monthlyReward = 50;
    uint256 internal _rewardPerDay = daysPerMonth / _monthlyReward;
    bool public premineSet_;
    address _owner;
    address[] internal stakeholders;
    address internal contractOwner = msg.sender;
    uint256 private _sessionsIds;
    uint256 private _stakeInstanceNumbers;
    
    // Time based variables
    uint256 internal _unlockTime;
    uint256 internal _monthlyClaimTime;
    uint256 private constant lockedDays = 1825; // 5 years in days
    uint256 internal constant daysPerMonth = 30; // We set a rough hardset time of 30 days per month
    uint256 internal constant blocksAday = 6500; // Rough rounded up blocks perday based on 14sec eth block time
    uint256 internal constant secondsAday = 86400;
    
    mapping(address => uint256) _balances;
    mapping(address => mapping (address => uint256)) allowed;
    mapping(address => uint256) internal stakes;
    mapping(address => uint256) internal stakesInstances;
    mapping(address => uint256) internal rewards;
    mapping(address => stakeData) stakeParams;
    mapping(uint256 => stakeData) sessionStakeData;
    
    struct stakeData { 
        address account;
        uint256 amount; 
        uint256 start; 
        uint256 end;
        uint256 session;
        uint256 stakeNumber;
    }
    
    constructor() public {
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(DEV_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    _setupRole(BURNER_ROLE, msg.sender);
    _setupRole(TEAM_ROLE, msg.sender);
    
    premineSet_ = false;

    }
    
    // ------------------------------------------------------------------------
    //                              Role Based Setup
    // ------------------------------------------------------------------------
    
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant TEAM_ROLE = keccak256("TEAM_ROLE");
    bytes32 public constant DEV_ROLE = keccak256("DEV_ROLE");
    
    function grantMinerRole(address account) public{
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Admin can only grant minter role.");
        grantRole(MINTER_ROLE, account);
    }
    function grantBurnerRole(address account) public{
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Admin can only grant burner role.");
        grantRole(BURNER_ROLE, account);
    }
    function grantTeamRole(address account) public{
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Admin can only grant team role.");
        grantRole(TEAM_ROLE, account);
    }
    function removeMinterRole(address account) public {
        require(hasRole(MINTER_ROLE, msg.sender), "Minters can only remove minter role.");
        revokeRole(MINTER_ROLE, account);
    }
    
    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, _msgSender()),
            "Caller is not a default admin"
        );
        _;
    }

    // ------------------------------------------------------------------------
    //                              Premine Functions
    // ------------------------------------------------------------------------

    function contractPremine(uint amount) public onlyAdmin() {
        require(!premineSet_ == true, "Premine has already been set");
        premineSet_ = true;
        _contractPremine = amount;
        _mint(msg.sender, amount);
    }
    
    // ------------------------------------------------------------------------
    // Team members only can change the monthly rewards per node
    // ------------------------------------------------------------------------
    function changeMonthlyReward(uint nodeReward) public {
        require(hasRole(TEAM_ROLE, msg.sender));
        _monthlyReward = nodeReward;
    }

    // ---------- STAKES ----------

    /**
     * @notice A method for a stakeholder to create a stake.
     * @param _stake The size of the stake to be created.
     */
    function createStake(uint256 _stake) public {
        require(_stake >= _balances[msg.sender], "Node Amount must be more then current balance.");
        require(_stake >= _minStakeamount, "Min node amount not met.");
        
        uint256 sessionId = _sessionsIds;
        uint256 stakeInstanceNumber = _stakeInstanceNumbers;
        
        // Set the time it takes to unstake
        _unlockTime = now.add(lockedDays.mul(secondsAday));
        
        // Set the time it takes to unstake
        _unlockTime = now + (lockedDays * 1 days);
        
        // Set the monthly claim time of the rewards
        _monthlyClaimTime = now + (daysPerMonth * 1 days);
        
         //Add the staker to the stake array
        (bool _isStakeholder, ) = isStakeholder(msg.sender);
        if(!_isStakeholder) stakeholders.push(msg.sender);
        
        _burn(msg.sender, _stake);
        if(stakes[msg.sender] == 0) addStakeholder(msg.sender);
        stakes[msg.sender] = stakes[msg.sender].add(_stake);
        
        
        
        if(stakeParams[msg.sender].stakesInstances == 0){
            stakesInstances[msg.sender] == 1;
            stakeParams[msg.sender].stakesInstances.add(1);
        } else if(stakeParams[msg.sender] >= 1){
            stakesInstances[msg.sender] = stakesInstances[msg.sender].add(1);
            stakeParams[msg.sender].stakesInstances.add(1);
        }
        
        
        
        _sessionsIds = _sessionsIds.add(1);
        
        
        
        
        _stakeInstanceNumbers = stakesInstances[msg.sender];
        
        stakeData memory stakeData_ = stakeData({
            account: msg.sender,
            amount: _stake,
            session: sessionId,
            stakeNumber: stakeInstanceNumber,
            start: now,
            end: _unlockTime
        });
        
        stakeParams[msg.sender] = stakeData_;
        sessionStakeData[sessionId] = stakeData_;
    }
    
    function returnSessionInfo(uint256 sessionID) public view returns (
        address account, 
        uint256 amount, 
        uint256 session,
        uint256 stakeNumber,
        uint256 start, 
        uint256 end){
        return (sessionStakeData[sessionID].account,
                sessionStakeData[sessionID].amount,
                sessionStakeData[sessionID].session,
                sessionStakeData[sessionID].stakeNumber,
                sessionStakeData[sessionID].start,
                sessionStakeData[sessionID].end
            );
    }

    /**
     * @notice A method for a stakeholder to remove a stake.
     * @param _stake The size of the stake to be removed.
     * Must meet the locked days requiremenet to remove the stake
     */
    function removeStake(uint256 _stake, address account) public {
        require(now >= stakeParams[account].start, "You need to wait for the end of the stake period to withdraw funds.");
        stakes[msg.sender] = stakes[msg.sender].sub(_stake);
        if(stakes[msg.sender] == 0) removeStakeholder(msg.sender);
        _mint(msg.sender, _stake);
    }

    /**
     * @notice A method to retrieve the stake for a stakeholder.
     * @param _stakeholder The stakeholder to retrieve the stake for.
     * @return uint256 The amount of wei staked.
     */
    function stakeOf(address _stakeholder) public view returns(uint256) {
        return stakes[_stakeholder];
    }

    /**
     * @notice A method to the aggregated stakes from all stakeholders.
     * @return uint256 The aggregated stakes from all stakeholders.
     */
    function totalStakes() public view returns(uint256) {
        uint256 _totalStakes = 0;
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            _totalStakes = _totalStakes.add(stakes[stakeholders[s]]);
        }
        return _totalStakes;
    }

    // ---------- STAKEHOLDERS ----------

    /**
     * @notice A method to check if an address is a stakeholder.
     * @param _address The address to verify.
     * @return bool, uint256 Whether the address is a stakeholder, 
     * and if so its position in the stakeholders array.
     */
    function isStakeholder(address _address) public view returns(bool, uint256) {
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            if (_address == stakeholders[s]) return (true, s);
        }
        return (false, 0);
    }

    /**
     * @notice A method to add a stakeholder.
     * @param _stakeholder The stakeholder to add.
     */
    function addStakeholder(address _stakeholder) public {
        require(_balances[msg.sender] <= _minStakeamount, "You need at least 10k tokens in order to create a stake!");
        (bool _isStakeholder, ) = isStakeholder(_stakeholder);
        if(!_isStakeholder) stakeholders.push(_stakeholder);
    }

    /**
     * @notice A method to remove a stakeholder.
     * @param _stakeholder The stakeholder to remove.
     */
    function removeStakeholder(address _stakeholder) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Admin can only remove stake holders.");
        (bool _isStakeholder, uint256 s) = isStakeholder(_stakeholder);
        if(_isStakeholder){
            stakeholders[s] = stakeholders[stakeholders.length - 1];
            stakeholders.pop();
        } 
    }

    // ---------- REWARDS ----------
    
    /**
     * @notice A method to allow a stakeholder to check his rewards.
     * @param _stakeholder The stakeholder to check rewards for.
     */
    function rewardOf(address _stakeholder) public view returns(uint256) {
        return rewards[_stakeholder];
    }

    /**
     * @notice A method to the aggregated rewards from all stakeholders.
     * @return uint256 The aggregated rewards from all stakeholders.
     */
    function totalRewards() public view returns(uint256) {
        uint256 _totalRewards = 0;
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            _totalRewards = _totalRewards.add(rewards[stakeholders[s]]);
        }
        return _totalRewards;
    }

    /* 
     * @notice A simple method that calculates the rewards for each stakeholder.
     * @param _stakeholder The stakeholder to calculate rewards for.
     */
    function calculateReward() public view returns(uint256) {
        return _monthlyReward;
    }

    /**
     * @notice A method to distribute rewards to all stakeholders.
     */
    function claimRewards() internal {
        //grantRole(MINTER_ROLE, msg.sender);
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            address stakeholder = stakeholders[s];
            uint256 reward = calculateReward();
            //rewards[stakeholder] = rewards[stakeholder].add(reward);
            emit Transfer(address(0), stakeholder, reward);
            //revokeRole(MINTER_ROLE, msg.sender);
        }
    }

    /**
     * @notice A method to allow a stakeholder to withdraw his rewards.
     */
    function withdrawReward() public {
        uint256 reward = rewards[msg.sender];
        rewards[msg.sender] = 0;
        _mint(msg.sender, reward);
    }
    
}