// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IStakingReward.sol";

contract StakingReward is IStakingReward, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice The staking token address
    IERC20 public immutable stakingToken;

    /// @notice The reward token address
    IERC20 public immutable rewardToken;

    /// @notice The period finish timestamp of reward token
    uint256 public periodFinish;

    /// @notice The reward rate of reward token
    uint256 public rewardRate;

    /// @notice The reward duration of reward token
    uint256 public rewardsDuration;

    /// @notice The last updated timestamp of reward token
    uint256 public lastUpdateTime;

    /// @notice The reward per token stored
    uint256 public rewardPerTokenStored;

    /// @notice The reward per token paid to users of  reward token
    mapping(address => uint256) public rewardPerTokenPaid;

    /// @notice The unclaimed rewards to users of reward token
    mapping(address => uint256) public rewards;

    /// @notice The total amount of the staking token staked in the contract
    uint256 private _totalSupply;

    /// @notice The user balance of the staking token staked in the contract
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        address initalOwner_,
        address stakingtoken_,
        address rewardToken_
    ) Ownable(initalOwner_) {
        stakingToken = IERC20(stakingtoken_);
        rewardToken = IERC20(rewardToken_);
    }

    /* ========== MODIFIERS ========== */
    /**
     * @notice Update the reward information.
     * @param user The user address
     */
    modifier updateReward(address user) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (user != address(0)) {
            rewards[user] = earned(user);
            rewardPerTokenPaid[user] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== VIEWS ========== */
    /**
     * @notice Return the total amount of the staking token staked in the contract.
     * @return The total supply
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Return user balance of the staking token staked in the contract.
     * @return The user balance
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Return the last time reward is applicable.
     * @return The last applicable timestamp
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return
            getBlockTimestamp() < periodFinish
                ? getBlockTimestamp()
                : periodFinish;
    }

    /**
     * @notice Return the reward token amount per staking token.
     * @return The reward token amount
     */
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (rewardRate *
                (lastTimeRewardApplicable() - lastUpdateTime) *
                1e18) /
            _totalSupply;
    }

    /**
     * @notice Return the reward token amount a user earned.
     * @param account The user address
     * @return The reward token amount
     */
    function earned(address account) public view override returns (uint256) {
        return
            (_balances[account] *
                (rewardPerToken() - rewardPerTokenPaid[account])) /
            1e18 +
            rewards[account];
    }

    /**
     * @notice Return the current block timestamp.
     * @return The current block timestamp
     */
    function getBlockTimestamp() public view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @notice Stake the staking token.
     * @param amount The amount of the staking token
     */
    function stake(
        uint256 amount
    ) external override nonReentrant updateReward(_msgSender()) whenNotPaused {
        if (amount == 0) {
            revert InvalidAmount();
        }
        _totalSupply = _totalSupply + amount;
        _balances[_msgSender()] = _balances[_msgSender()] + amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(_msgSender(), amount);
    }

    function withdraw(
        uint256 amount
    ) public override nonReentrant updateReward(_msgSender()) whenNotPaused {
        if (amount == 0) {
            revert InvalidAmount();
        }

        _totalSupply = _totalSupply - amount;
        _balances[_msgSender()] = _balances[_msgSender()] - amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(_msgSender(), amount);
    }

    /**
     * @notice Claim rewards for an account.
     * @dev This function can only be called by helper.
     */
    function getReward()
        public
        nonReentrant
        updateReward(_msgSender())
        whenNotPaused
    {
        uint256 reward = rewards[_msgSender()];

        if (reward > 0) {
            rewards[_msgSender()] = 0;
            rewardToken.safeTransfer(_msgSender(), reward);
            emit RewardPaid(_msgSender(), reward);
        }
    }

    /**
     * @notice Withdraw all the staked tokens and claim rewards.
     */
    function exit() external {
        withdraw(_balances[_msgSender()]);
        getReward();
    }

    /**
     * @notice Set new reward amount.
     * @dev Make sure the admin deposits `reward` of reward tokens into the contract before calling this function.
     * @param reward The reward amount
     */
    function notifyRewardAmount(
        uint256 reward
    ) external onlyOwner updateReward(address(0)) {
        if (getBlockTimestamp() >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - getBlockTimestamp();
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint256 balance = rewardToken.balanceOf(address(this));
        require(
            rewardRate <= balance / rewardsDuration,
            "reward rate too high"
        );

        lastUpdateTime = getBlockTimestamp();
        periodFinish = getBlockTimestamp() + rewardsDuration;
        emit RewardAdded(reward);
    }

    /**
     * @notice Set the rewards duration.
     * @param duration The new duration
     */
    function setRewardsDuration(uint256 duration) external onlyOwner {
        require(
            getBlockTimestamp() > periodFinish,
            "previous rewards not complete"
        );
        if (getBlockTimestamp() <= periodFinish) {
            revert UnfinnishedPreviousReward();
        }
        rewardsDuration = duration;
        emit RewardsDurationUpdated(duration);
    }

    /**
     * @notice Pause the staking.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the staking.
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
