// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IMOR20} from "../interfaces/L2/IMOR20.sol";
import {IL2MessageReceiver} from "../interfaces/L2/IL2MessageReceiver.sol";

contract L2MessageReceiver is IL2MessageReceiver, OwnableUpgradeable {
    /**
     * @notice MOR20 token
     */
    address public rewardToken;

    /**
     * @notice L2Receiver config
     */
    Config public config;

    /**
     * @notice ChainId => ((Sender, Receiver) => (nonce => payload hash))
     */
    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;

    constructor() {
        _disableInitializers();
    }

    /**
     * @inheritdoc IL2MessageReceiver
     */
    function L2MessageReceiver__init(address rewardToken_, Config calldata config_) external override initializer {
        __Ownable_init();

        rewardToken = rewardToken_;
        config = config_;
    }

    /**
     * @inheritdoc IL2MessageReceiver
     */
    function setLzSender(address lzSender_) external onlyOwner {
        require(lzSender_ != address(0), "L2MR: invalid sender");

        config.sender = lzSender_;
    }

    /**
     * @inheritdoc IL2MessageReceiver
     */
    function lzReceive(
        uint16 senderChainId_,
        bytes memory senderAndReceiverAddresses_,
        uint64 nonce_,
        bytes memory payload_
    ) external {
        require(_msgSender() == config.gateway, "L2MR: invalid gateway");

        _blockingLzReceive(senderChainId_, senderAndReceiverAddresses_, nonce_, payload_);
    }

    /**
     * @inheritdoc IL2MessageReceiver
     */
    function nonblockingLzReceive(
        uint16 senderChainId_,
        bytes memory senderAndReceiverAddresses_,
        bytes memory payload_
    ) public {
        require(_msgSender() == address(this), "L2MR: invalid caller");

        _nonblockingLzReceive(senderChainId_, senderAndReceiverAddresses_, payload_);
    }

    /**
     * @inheritdoc IL2MessageReceiver
     */
    function retryMessage(
        uint16 senderChainId_,
        bytes memory senderAndReceiverAddresses_,
        uint64 nonce_,
        bytes memory payload_
    ) external {
        bytes32 payloadHash_ = failedMessages[senderChainId_][senderAndReceiverAddresses_][nonce_];
        require(payloadHash_ != bytes32(0), "L2MR: no stored message");
        require(keccak256(payload_) == payloadHash_, "L2MR: invalid payload");

        delete failedMessages[senderChainId_][senderAndReceiverAddresses_][nonce_];

        _nonblockingLzReceive(senderChainId_, senderAndReceiverAddresses_, payload_);

        emit RetryMessageSuccess(senderChainId_, senderAndReceiverAddresses_, nonce_, payload_);
    }

    function _blockingLzReceive(
        uint16 senderChainId_,
        bytes memory senderAndReceiverAddresses_,
        uint64 nonce_,
        bytes memory payload_
    ) private {
        try
            IL2MessageReceiver(address(this)).nonblockingLzReceive(
                senderChainId_,
                senderAndReceiverAddresses_,
                payload_
            )
        {
            emit MessageSuccess(senderChainId_, senderAndReceiverAddresses_, nonce_, payload_);
        } catch (bytes memory reason_) {
            failedMessages[senderChainId_][senderAndReceiverAddresses_][nonce_] = keccak256(payload_);

            emit MessageFailed(senderChainId_, senderAndReceiverAddresses_, nonce_, payload_, reason_);
        }
    }

    function _nonblockingLzReceive(
        uint16 senderChainId_,
        bytes memory senderAndReceiverAddresses_,
        bytes memory payload_
    ) private {
        require(senderChainId_ == config.senderChainId, "L2MR: invalid sender chain ID");

        address sender_;
        assembly {
            sender_ := mload(add(senderAndReceiverAddresses_, 20))
        }
        require(sender_ == config.sender, "L2MR: invalid sender address");

        (address user_, uint256 amount_) = abi.decode(payload_, (address, uint256));

        IMOR20(rewardToken).mint(user_, amount_);
    }
}
