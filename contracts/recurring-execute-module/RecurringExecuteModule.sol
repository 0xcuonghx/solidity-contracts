// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC7579ExecutorBase} from "modulekit/Modules.sol";
import {IERC7579Account} from "modulekit/Accounts.sol";
import {ModeLib} from "erc7579/lib/ModeLib.sol";
import {BokkyPooBahsDateTimeLibrary} from "./libs/BokkyPooBahsDateTimeLibrary.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ERC20Integration} from "modulekit/Integrations.sol";

contract RecurringExecuteModule is ERC7579ExecutorBase {
    using BokkyPooBahsDateTimeLibrary for *;
    using ERC20Integration for IERC20;

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    event RecurringExecutionAdded(
        address indexed smartAccount,
        ExecutionBasis basis,
        address receiver,
        address token,
        uint256 amount,
        uint8 executionDay,
        uint8 executionHourStart,
        uint8 executionHourEnd
    );
    event RecurringExecutionRemoved(address indexed smartAccount);
    event RecurringExecutionTriggered(address indexed smartAccount);

    error InvalidExecutionDay();
    error InvalidExecutionHour();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDailyExecution();
    error InvalidWeeklyExecution();
    error InvalidMonthlyExecution();
    error NoRecurringExecution();

    enum ExecutionBasis {
        Daily,
        Weekly,
        Monthly
    }

    struct RecurringExecution {
        ExecutionBasis basis;
        address receiver;
        address token;
        uint256 amount;
        uint8 executionDay;
        uint8 executionHourStart;
        uint8 executionHourEnd;
        uint32 lastExecutionTimestamp;
    }

    mapping(address smartAccount => RecurringExecution)
        private _recurringExecutions;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * Initialize the module with the given data
     *
     * @param data The data to initialize the module with
     */
    function onInstall(bytes calldata data) external override {
        (
            ExecutionBasis basis,
            address receiver,
            address token,
            uint256 amount,
            uint8 executionDay,
            uint8 executionHourStart,
            uint8 executionHourEnd
        ) = abi.decode(
                data,
                (ExecutionBasis, address, address, uint256, uint8, uint8, uint8)
            );

        _addRecurringExecution(
            basis,
            receiver,
            token,
            amount,
            executionDay,
            executionHourStart,
            executionHourEnd
        );
    }

    /**
     * De-initialize the module with the given data
     *
     */
    function onUninstall(bytes calldata) external override {
        _removeRecurringExecution();
    }

    /**
     * Check if the module is initialized
     * @param smartAccount The smart account to check
     *
     * @return true if the module is initialized, false otherwise
     */
    function isInitialized(address smartAccount) external view returns (bool) {
        return _recurringExecutions[smartAccount].receiver != address(0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     MODULE LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * ERC-7579 does not define any specific interface for executors, so the
     * executor can implement any logic that is required for the specific usecase.
     */

    /**
     * Execute the given data
     * @dev This is an example function that can be used to execute arbitrary data
     * @dev This function is not part of the ERC-7579 standard
     *
     * @param smartAccount The smart account address
     */
    function execute(address smartAccount) external {
        if (smartAccount == address(0)) {
            revert InvalidAddress();
        }
        RecurringExecution memory executionData = _recurringExecutions[
            smartAccount
        ];

        if (executionData.executionHourStart == 0) {
            revert NoRecurringExecution();
        }
        if (
            executionData.basis == ExecutionBasis.Daily &&
            !_isValidDaily(executionData)
        ) {
            revert InvalidDailyExecution();
        } else if (
            executionData.basis == ExecutionBasis.Weekly &&
            !_isValidWeekly(executionData)
        ) {
            revert InvalidWeeklyExecution();
        } else if (
            executionData.basis == ExecutionBasis.Monthly &&
            !_isValidMonthly(executionData)
        ) {
            revert InvalidMonthlyExecution();
        }

        _recurringExecutions[smartAccount].lastExecutionTimestamp = uint32(
            block.timestamp
        );

        IERC20(executionData.token).safeTransfer({
            account: smartAccount,
            to: executionData.receiver,
            amount: executionData.amount
        });

        emit RecurringExecutionTriggered(smartAccount);
    }

    function recurringExecutionOf(
        address smartAccount
    ) public view returns (RecurringExecution memory) {
        return _recurringExecutions[smartAccount];
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     INTERNAL
    //////////////////////////////////////////////////////////////////////////*/
    function _addRecurringExecution(
        ExecutionBasis basis,
        address receiver,
        address token,
        uint256 amount,
        uint8 executionDay,
        uint8 executionHourStart,
        uint8 executionHourEnd
    ) internal {
        if (amount == 0) {
            revert InvalidAmount();
        }

        if (receiver == address(0)) {
            revert InvalidAddress();
        }

        if (executionDay == 0) {
            revert InvalidExecutionDay();
        } else if (basis == ExecutionBasis.Monthly && executionDay >= 29) {
            revert InvalidExecutionDay();
        } else if (basis == ExecutionBasis.Weekly && executionDay >= 8) {
            revert InvalidExecutionDay();
        }

        if (
            executionHourStart == 0 ||
            executionHourEnd >= 23 ||
            executionHourStart >= executionHourEnd
        ) {
            revert InvalidExecutionHour();
        }

        _recurringExecutions[msg.sender] = RecurringExecution({
            basis: basis,
            receiver: receiver,
            token: token,
            amount: amount,
            executionDay: executionDay,
            executionHourStart: executionHourStart,
            executionHourEnd: executionHourEnd,
            lastExecutionTimestamp: 0
        });

        emit RecurringExecutionAdded(
            msg.sender,
            basis,
            receiver,
            token,
            amount,
            executionDay,
            executionHourStart,
            executionHourEnd
        );
    }

    function _removeRecurringExecution() internal {
        delete _recurringExecutions[msg.sender];
        emit RecurringExecutionRemoved(msg.sender);
    }

    function _isValidDaily(
        RecurringExecution memory executionData
    ) internal view returns (bool) {
        return
            _isPastDay(executionData.lastExecutionTimestamp) &&
            _isBetweenHours(
                executionData.executionHourStart,
                executionData.executionHourEnd
            );
    }

    function _isValidWeekly(
        RecurringExecution memory executionData
    ) internal view returns (bool) {
        return
            _isPastWeek(executionData.lastExecutionTimestamp) &&
            _isOnDayOfWeekAndBetweenHours(
                executionData.executionDay,
                executionData.executionHourStart,
                executionData.executionHourEnd
            );
    }

    function _isValidMonthly(
        RecurringExecution memory executionData
    ) internal view returns (bool) {
        return
            _isPastMonth(executionData.lastExecutionTimestamp) &&
            _isOnDayAndBetweenHours(
                executionData.executionDay,
                executionData.executionHourStart,
                executionData.executionHourEnd
            );
    }

    function _isOnDayAndBetweenHours(
        uint8 day,
        uint8 hourStart,
        uint8 hourEnd
    ) internal view returns (bool) {
        return
            block.timestamp.getDay() == day &&
            block.timestamp.getHour() >= hourStart &&
            block.timestamp.getHour() < hourEnd;
    }

    function _isOnDayOfWeekAndBetweenHours(
        uint8 day,
        uint8 hourStart,
        uint8 hourEnd
    ) internal view returns (bool) {
        return
            block.timestamp.getDayOfWeek() == day &&
            block.timestamp.getHour() >= hourStart &&
            block.timestamp.getHour() < hourEnd;
    }

    function _isBetweenHours(
        uint8 hourStart,
        uint8 hourEnd
    ) internal view returns (bool) {
        return
            block.timestamp.getHour() >= hourStart &&
            block.timestamp.getHour() < hourEnd;
    }

    function _isPastMonth(uint256 previousTime) internal view returns (bool) {
        return
            block.timestamp.getYear() > previousTime.getYear() ||
            block.timestamp.getMonth() > previousTime.getMonth();
    }

    function _isPastDay(uint256 previousTime) internal view returns (bool) {
        return
            block.timestamp.getYear() > previousTime.getYear() ||
            block.timestamp.getMonth() > previousTime.getMonth() ||
            block.timestamp.getDay() > previousTime.getDay();
    }

    function _isPastWeek(uint256 previousTime) internal view returns (bool) {
        return
            block.timestamp.getYear() > previousTime.getYear() ||
            block.timestamp.getMonth() > previousTime.getMonth() ||
            (block.timestamp.getDay() - 1) / 7 >
            (previousTime.getDay() - 1) / 7;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     METADATA
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * The name of the module
     *
     * @return name The name of the module
     */
    function name() external pure returns (string memory) {
        return "RecurringExecuteModule";
    }

    /**
     * The version of the module
     *
     * @return version The version of the module
     */
    function version() external pure returns (string memory) {
        return "0.0.1";
    }

    /**
     * Check if the module is of a certain type
     *
     * @param typeID The type ID to check
     *
     * @return true if the module is of the given type, false otherwise
     */
    function isModuleType(
        uint256 typeID
    ) external pure override returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }
}
