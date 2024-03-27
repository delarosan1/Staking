// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./tokenPay.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint);
}

contract ENOStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public stakingToken;
    IERC20 public enoToken;
    IERC20 public usdtAddress;
    TokenPay public tokenpay;

    struct StakingInfo {
        uint lpAmount;
        uint enoAmount;
        uint usdtAmount;
        uint endTime;
        uint multiplier;
        uint stakingDuration; 
    }

    bool public isPaused;
    bool public stakingIsPaused;
    
    uint public penaltyRate = 25;
    address public penaltyWallet = 0x53b6a15f204Af45613Ca6E559a1701A1Ab040FD6; // ENO CAJA

    uint public stakingPeriod = 1 minutes; // 30 days o 1 minutes para pruebas
    bool public inTestingPeriod = true;

    mapping(address => StakingInfo[]) public stakings;
    mapping(uint => uint32) public multiplierMapping;

    event Staked(address indexed user, uint lpAmount, uint enoAmount, uint usdtAmount, uint endTime, uint multiplier, uint stakingDuration);
    event Withdrawn(address indexed user, uint lpAmount, uint rewardAmount);
    event MultiplierUpdated(uint durationInMonths, uint32 newMultiplier);

    modifier whenNotPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    modifier whenNotStakingPaused() {
        require(!stakingIsPaused, "Staking is paused");
        _;
    }

    constructor(
        address _stakingTokenAddress, 
        address _enoToken, 
        address _usdtAddress,
        TokenPay _tokenpay) Ownable(msg.sender)
    {
        require(_stakingTokenAddress != address(0), "Staking token address cannot be the zero address");
        require(_enoToken != address(0), "ENO token address cannot be the zero address");
        require(_usdtAddress != address(0), "USDT address cannot be the zero address");

        stakingToken = IERC20(_stakingTokenAddress);
        enoToken = IERC20(_enoToken);
        usdtAddress = IERC20(_usdtAddress);
        tokenpay = _tokenpay;
    }

    function setPenaltyRate(uint _newRate) external onlyOwner {
        require(_newRate <= 100, "Penalty rate should be <= 100");
        penaltyRate = _newRate;
    }

    function disableTestingPeriod() public onlyOwner {
        require(inTestingPeriod, "Updating staking period has been disabled");
        stakingPeriod = 30 days;
        inTestingPeriod = false;
    }

    function enoPerLPToken(uint _lpAmount) public view returns (uint enoAmount) {
        IUniswapV2Pair lpPair = IUniswapV2Pair(address(stakingToken)); // stakingToken es el token LP
        (uint112 reserve0, uint112 reserve1,) = lpPair.getReserves();
        uint totalSupplyLP = lpPair.totalSupply();

        uint112 reserveENO = lpPair.token0() == address(enoToken) ? reserve0 : reserve1;

        enoAmount = _lpAmount * reserveENO / totalSupplyLP;
    }

    function usdtPerLPToken(uint _lpAmount) public view returns (uint usdtAmount) {
        IUniswapV2Pair lpPair = IUniswapV2Pair(address(stakingToken));
        (uint112 reserve0, uint112 reserve1,) = lpPair.getReserves();
        uint totalSupplyLP = lpPair.totalSupply();

        uint112 reserveUSDT = lpPair.token0() == address(usdtAddress) ? reserve0 : reserve1;

        usdtAmount = _lpAmount * reserveUSDT / totalSupplyLP;
    }

    function updateMultiplier(uint _durationInMonths, uint32 _multiplier) public onlyOwner {
        require(_multiplier > 0, "Multiplier must be greater than 0");
        require(
            _durationInMonths == 1 || _durationInMonths == 3 || _durationInMonths == 6 || 
            _durationInMonths == 12 || _durationInMonths == 24 || _durationInMonths == 48, 
            "Invalid duration"
        );
        multiplierMapping[_durationInMonths] = _multiplier;
        emit MultiplierUpdated(_durationInMonths, _multiplier);
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

    function stake(uint _lpAmount, uint _months) public whenNotPaused whenNotStakingPaused{
        require(_months == 1 || _months == 3 || _months == 6 || _months == 12 || _months == 24 || _months == 48, "Invalid staking duration");
        require(_lpAmount > 0, "Invalid staking amount");

        uint enoAmount = enoPerLPToken(_lpAmount);
        uint usdtAmount = usdtPerLPToken(_lpAmount);
        uint32 multiplier = getMultiplier(_months);

        stakingToken.safeTransferFrom(msg.sender, address(this), _lpAmount);
        stakings[msg.sender].push(StakingInfo({
            lpAmount: _lpAmount,
            enoAmount: enoAmount,
            usdtAmount: usdtAmount,
            endTime: block.timestamp + (_months * stakingPeriod), 
            multiplier: multiplier,
            stakingDuration: _months 
        }));
        emit Staked(msg.sender, _lpAmount, enoAmount, usdtAmount, block.timestamp + _months * 1 minutes, multiplier, _months);
    }

    function withdraw(uint _index) public whenNotPaused nonReentrant{
        require(_index < stakings[msg.sender].length, "Invalid stake index");

        StakingInfo storage info = stakings[msg.sender][_index];
        uint lpAmountToReturn = info.lpAmount;
        uint rewardAmount = 0;

        if (block.timestamp >= info.endTime) {
            // Si el periodo de staking ha concluido, calcula la recompensa.
            rewardAmount = (info.enoAmount * info.multiplier) / 10000;
            rewardAmount -= info.enoAmount; // Asegúrate de ajustar esto según tu lógica de recompensa.
            /* enoToken.safeTransfer(msg.sender, rewardAmount); */ 
            tokenpay.fakeMint(msg.sender, rewardAmount); // Transfiere los tokens ENO de recompensa.
        } else {
            // Si se retira antes de tiempo, aplica una penalización.
            uint penaltyAmount = (info.lpAmount * penaltyRate) / 100;
            if(penaltyAmount > 0) {
                stakingToken.safeTransfer(penaltyWallet, penaltyAmount);
            }
            lpAmountToReturn -= penaltyAmount; // Reduce la cantidad de LP a devolver por la penalización.
        }

        // Devuelve los tokens LP stakeados (ajustados por cualquier penalización).
        if (lpAmountToReturn > 0) {
            stakingToken.safeTransfer(msg.sender, lpAmountToReturn);
        }

        emit Withdrawn(msg.sender, lpAmountToReturn, rewardAmount);

        // Elimina la información de staking para evitar la reutilización del índice.
        stakings[msg.sender][_index] = stakings[msg.sender][stakings[msg.sender].length - 1];
        stakings[msg.sender].pop();
    }

    function getStakes(address _owner) public view returns (StakingInfo[] memory) {
        return stakings[_owner];
    }

    function getMultiplier(uint _months) internal view returns (uint32) {
        require(multiplierMapping[_months] > 0, "Invalid staking duration");
        return multiplierMapping[_months];
    }

    function getContractBalance() public view returns (uint) {
        return stakingToken.balanceOf(address(this));
    }

    function getTotalLPStakedByUser(address _user) public view returns (uint) {
        uint totalLPStaked = 0;
        for (uint i = 0; i < stakings[_user].length; i++) {
            totalLPStaked += stakings[_user][i].lpAmount;
        }
        return totalLPStaked;
    }
    
    function getTotalENOStakedByUser(address _user) public view returns (uint) {
        uint totalStaked = 0;
        for (uint i = 0; i < stakings[_user].length; i++) {
            totalStaked += stakings[_user][i].enoAmount;
        }
        return totalStaked;
    }

    function getTotalUSDTStakedByUser(address _user) public view returns (uint) {
        uint totalUSDT = 0;
        for (uint i = 0; i < stakings[_user].length; i++) {
            totalUSDT += stakings[_user][i].usdtAmount;
        }
        return totalUSDT;
    }

    function getActiveStakingsCount(address _user) public view returns (uint) {
        return stakings[_user].length;
    }

    function fakeMint(address _to, uint256 _amount) internal {
        tokenpay.fakeMint(_to, _amount);
    }

}
