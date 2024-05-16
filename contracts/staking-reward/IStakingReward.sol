// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

error InvalidAmount();
error UnfinnishedPreviousReward();

interface IStakingReward {
    /**
     * @notice Emitted when user staked
     */
    event Staked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when user withdrew
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when rewards are paied
     */
    event RewardPaid(address indexed user, uint256 reward);

    /**
     * @notice Emitted when a reward duration is updated
     */
    event RewardsDurationUpdated(uint256 newDuration);

    /**
     * @notice Emitted when new reward tokens are added
     */
    event RewardAdded(uint256 reward);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function exit() external;
}
