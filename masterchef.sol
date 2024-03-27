// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./ENOToken.sol";
import "./tokenPay.sol";

contract MasterChefV1 is Ownable, ReentrancyGuard { 
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; 
        uint256 pendingReward;
    }

     struct PoolInfo {
        IERC20 lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardTokenPerShare;
    }

    ENOToken public token;
    TokenPay public tokenpay;

    address public dev;
    uint256 public tokenPerBlock;

    bool public isPaused;
    bool public stakingIsPaused;


    PoolInfo[] public poolInfo;
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    uint256 public totalAllocation = 0;
    uint256 public startBlock;
    uint256 public BONUS_MULTIPLIER = 1;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        ENOToken _token,
        TokenPay _tokenpay,
        address _dev,
        uint256 _tokenPerBlock,
        uint256 _startBlock
    ) Ownable(msg.sender){
        token = _token;
        tokenpay = _tokenpay;
        dev = _dev;
        tokenPerBlock = _tokenPerBlock;
        startBlock = _startBlock;

        poolInfo.push(PoolInfo({
            lpToken: _token,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            rewardTokenPerShare: 0
        }));
        totalAllocation = 1000;
    }

    modifier validatePool(uint256 _pid) {
        require(_pid < poolInfo.length, "pool Id Invalid");
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    modifier whenNotStakingPaused() {
        require(!stakingIsPaused, "Staking is paused");
        _;
    }

    function pauseContract() external onlyOwner {
        isPaused = true;
    }

    function unpauseContract() external onlyOwner {
        isPaused = false;
    }

    function pauseStakingContract() external onlyOwner {
        stakingIsPaused = true;
    }

    function unpauseStakingContract() external onlyOwner {
        stakingIsPaused = false;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function checkPoolDuplicate(IERC20 _lpToken) public view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "add: existing pool");
        }
    }

    function add(uint256 _allocPoint, IERC20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        checkPoolDuplicate(_lpToken);
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocation = totalAllocation.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            rewardTokenPerShare: 0
        }));
        updateStakingPool();
    }

    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocation = totalAllocation.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocation = totalAllocation.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    function pendingReward(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 rewardTokenPerShare = pool.rewardTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocation);
            rewardTokenPerShare = rewardTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(rewardTokenPerShare).div(1e12).sub(user.pendingReward);
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocation);
        uint256 reward = pendingReward(_pid, msg.sender);

        if (reward > 0){
            tokenpay.fakeMint(dev, reward.div(10));
            tokenpay.fakeMint(address(this), reward);
        }
        
        pool.rewardTokenPerShare = pool.rewardTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    function stake(uint256 _pid, uint256 _amount) public validatePool(_pid) whenNotPaused whenNotStakingPaused {
        require(_amount > 0, "Amount must be greater than 0");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 rewards = pendingReward(_pid, msg.sender);
            if(rewards > 0) {
                safeTokenTransfer(msg.sender, rewards);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.pendingReward = user.amount.mul(pool.rewardTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function autoCompound(uint256 _pid) public whenNotPaused whenNotStakingPaused {
        uint256 rewards = pendingReward(_pid, msg.sender);
        require(rewards > 0, "Dont have Rewards");
        withdrawToken(_pid);
        stake(_pid, rewards);
    }


    function withdrawToken(uint256 _pid) public whenNotPaused {
        uint256 rewards = pendingReward(_pid, msg.sender);
        require(rewards > 0, "Dont have Rewards");
        unstake(_pid, 0);
    }

    function unstake(uint256 _pid, uint256 _amount) public validatePool(_pid) whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);

        uint256 rewards = pendingReward(_pid, msg.sender);
        if(rewards > 0) {
            safeTokenTransfer(msg.sender, rewards);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.pendingReward = user.amount.mul(pool.rewardTokenPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

/*     function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.pendingReward = 0;
    } */

    function getPoolInfo(uint256 _pid) public view
    returns(address lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 rewardTokenPerShare) {
        return (address(poolInfo[_pid].lpToken),
            poolInfo[_pid].allocPoint,
            poolInfo[_pid].lastRewardBlock,
            poolInfo[_pid].rewardTokenPerShare);
    }

    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal){
        token.transfer(_to, tokenBal);
        }
        else {
        token.transfer(_to, _amount);
        }
    } 

    function fakeMint(address _to, uint256 _amount) internal {
        tokenpay.fakeMint(_to, _amount);
    }

    function changeDev(address _dev) public {
        require(msg.sender == dev, "Not Authorized");
        dev = _dev;
    }
}