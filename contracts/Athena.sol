// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

// import "hardhat/console.sol";

contract Athena is Ownable {
    using SafeERC20 for IERC20Metadata;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    uint256 public constant MAX_SPAN = 3;
    uint256 public constant MAX_LEVEL = 5;
    uint256 public constant CLAIM_EPOCH = 30 days;

    IERC20Metadata public immutable USDT;
    uint8 private immutable usdtDecimals;

    struct Earnings {
        uint256 totalPayout;
        uint256 referralCount;
        uint256 pendingPayout;
        uint256 lastClaimTimestamp;
    }

    struct User {
        uint256 package;
        uint256 level;
        address referrer;
        address parent;
        address[] directs;
    }

    mapping(address => bool) public hasRegistered;
    mapping(address => User) public userInfo;
    mapping(address => Earnings) public userEarnings;

    DoubleEndedQueue.Bytes32Deque private queue;

    event ApprovedKYC(address user, address referrer);
    event LevelUp(address user, uint256 newLevel);

    error InvalidPackage(uint256 package);
    error RegistrationExists(address user);
    error DepositDoesNotExist(address user);
    error DepositExists(address user, uint256 package);
    error InsufficientAmountClaimable(uint256 timeElapsed);

    constructor(IERC20Metadata usdt) Ownable(msg.sender) {
        USDT = usdt;
        usdtDecimals = USDT.decimals();

        // TODO
        // Contract is bricked upon deployment, as no registered user
    }

    function getAmountForPackage(uint256 package) public view returns(uint256) {
        uint256 unit = 10**usdtDecimals;

        if (package == 1) {
            return 20 * unit;
        } else if (package == 2) {
            return 45 * unit;
        } else if (package == 3) {
            return 90 * unit;
        } else if (package == 4) {
            return 180 * unit;
        } else if (package == 5) {
            return 335 * unit;
        } else {
            revert InvalidPackage(package);
        }
    }

    function getAmountForMonthlyROI(uint256 package, uint256 level) public view returns(uint256) {
        if (package == 1) {
            return (10 + level) * getAmountForPackage(package) / 100;
        } else if (package == 2) {
            return (12 + level) * getAmountForPackage(package) / 100;
        } else if (package == 3) {
            return (15 + level) * getAmountForPackage(package) / 100;
        } else if (package == 4) {
            return (17 + level) * getAmountForPackage(package) / 100;
        } else if (package == 5) {
            return (20 + level) * getAmountForPackage(package) / 100;
        } else {
            revert InvalidPackage(package);
        }
    }

    function getAmountForReferrer(uint256 package) public view returns(uint256) {
        if (package == 1) {
            return 5 * getAmountForPackage(package) / 100;
        } else if (package == 2) {
            return 6 * getAmountForPackage(package) / 100;
        } else if (package == 3) {
            return 7 * getAmountForPackage(package) / 100;
        } else if (package == 4) {
            return 8 * getAmountForPackage(package) / 100;
        } else if (package == 5) {
            return 10 * getAmountForPackage(package) / 100;
        } else {
            revert InvalidPackage(package);
        }
    }

    function getUserDirects(address user) external view returns(address[] memory) {
        return userInfo[user].directs;
    }

    function hasDeposited(address user) public view returns(bool) {
        return userInfo[user].package != 0;
    }

    function register(address referrer) external {
        address user = msg.sender;

        // ensure user is not already registered
        if(hasRegistered[user]) {
            revert RegistrationExists(user);
        }

        // ensure referrer is deposited
        if(!hasDeposited(referrer)) {
            revert DepositDoesNotExist(referrer);
        }
        // set to registered
        hasRegistered[user] = true;

        // set referrer
        User memory u;
        u.referrer = referrer;
        userInfo[user] = u;

        // increment referral count
        userEarnings[referrer].referralCount += 1;

        // emit event
        emit ApprovedKYC(user, referrer);
    }

    function deposit(uint256 package) external {
        // check registration
        if(!hasRegistered[msg.sender]) {
            revert RegistrationExists(msg.sender);
        }

        // transfer-in usdt
        uint256 amount = getAmountForPackage(package);
        USDT.safeTransferFrom(address(msg.sender), address(this), amount);

        User storage user = userInfo[msg.sender];

        // check not already deposited
        if(user.package != 0) {
            revert DepositExists(msg.sender, user.package);
        }

        // add referral fee to-be claimed
        uint256 amountForReferrer = getAmountForReferrer(package);
        userEarnings[user.referrer].pendingPayout += amountForReferrer;

        // set user struct details
        user.package = package;
        userEarnings[msg.sender].lastClaimTimestamp = block.timestamp;

        // add user connections
        _addConnections(msg.sender, user.referrer);
    }

    function claim() external {
        Earnings storage earnings = userEarnings[msg.sender];
        User memory user = userInfo[msg.sender];

        // check 1 epoch has passed
        uint256 timeElapsed = block.timestamp - earnings.lastClaimTimestamp;
        if(timeElapsed < CLAIM_EPOCH && earnings.pendingPayout == 0) {
            revert InsufficientAmountClaimable(timeElapsed);
        }
        // update last claim timestamp
        uint256 epochsElapsed = timeElapsed/CLAIM_EPOCH;
        uint256 payout = earnings.pendingPayout + epochsElapsed * getAmountForMonthlyROI(user.package, user.level);
        earnings.lastClaimTimestamp += epochsElapsed * CLAIM_EPOCH;

        // update state variables
        earnings.pendingPayout = 0;
        earnings.totalPayout += payout;

        USDT.transfer(msg.sender, payout);
    }

    function _addConnections(address user, address referrer) internal {

        DoubleEndedQueue.clear(queue);
        DoubleEndedQueue.pushBack(queue, _toBytes32(referrer));

        while(!DoubleEndedQueue.empty(queue)) {
            address current = _toAddress(DoubleEndedQueue.popFront(queue));
            uint256 length = userInfo[current].directs.length;
            if(length < MAX_SPAN) {
                userInfo[current].directs.push(user);
                userInfo[user].parent = current;

                if(length == MAX_SPAN - 1) {
                    _promoteChain(current);
                }
                return;
            } else {
                for (uint i = 0; i < MAX_SPAN; i++) {
                    DoubleEndedQueue.pushBack(queue, _toBytes32(userInfo[current].directs[i]));
                }
            }
        }
    }

    function _promoteChain(address user) internal {
        userInfo[user].level += 1;
        emit LevelUp(user, userInfo[user].level);

        address parent = userInfo[user].parent;
        while(parent != address(0)) {
            User memory current = userInfo[parent];
            uint256 length = current.directs.length;
            if(length < MAX_SPAN || current.level == MAX_LEVEL) {
                break;
            }
            uint256 minDirectLevel = MAX_LEVEL;
            for (uint i = 0; i < length; i++) {
                if(userInfo[current.directs[i]].level < minDirectLevel) {
                    minDirectLevel = userInfo[current.directs[i]].level;
                }
            }
            if(current.level == minDirectLevel) {
                userInfo[parent].level += 1;
                emit LevelUp(parent, userInfo[parent].level);
                parent = current.parent;
            } else {
                break;
            }
        }
    }

    function _toBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function _toAddress(bytes32 a) internal pure returns (address) {
        return address(uint160(uint256(a)));
    }
}
