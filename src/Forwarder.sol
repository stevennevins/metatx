// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC2771Forwarder} from "@openzeppelin/metatx/ERC2771Forwarder.sol";
import {ERC2771Context} from "@openzeppelin/metatx/ERC2771Context.sol";
import {Address} from "@openzeppelin/utils/Address.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";
import {LibZip} from "solady/utils/LibZip.sol";

contract Forwarder is ERC2771Forwarder {
    using LibZip for bytes;
    using ECDSA for bytes32;

    constructor() ERC2771Forwarder("Forwader") {}

    function executeBatch(bytes calldata compressedData) external payable {
        bytes memory data = compressedData.flzDecompress();
        (ForwardRequestData[] memory requests, address payable refundReceiver) = abi.decode(
            data,
            (ForwardRequestData[], address)
        );

        bool atomic = refundReceiver == address(0);
        uint256 requestsValue;
        uint256 refundValue;

        for (uint256 i; i < requests.length; ++i) {
            requestsValue += requests[i].value;
            bool success = _executeMem(requests[i], atomic);
            if (!success) {
                refundValue += requests[i].value;
            }
        }

        // The batch should revert if there's a mismatched msg.value provided
        // to avoid request value tampering
        if (requestsValue != msg.value) {
            revert ERC2771ForwarderMismatchedValue(requestsValue, msg.value);
        }

        // Some requests with value were invalid (possibly due to frontrunning).
        // To avoid leaving ETH in the contract this value is refunded.
        if (refundValue != 0) {
            // We know refundReceiver != address(0) && requestsValue == msg.value
            // meaning we can ensure refundValue is not taken from the original contract's balance
            // and refundReceiver is a known account.
            Address.sendValue(refundReceiver, refundValue);
        }
    }

    function execute(bytes calldata compressedData) external payable {
        bytes memory data = compressedData.flzDecompress();

        ForwardRequestData memory request = abi.decode(data, (ForwardRequestData));
        _executeMem(request, true);
    }
    function _validateMem(
        ForwardRequestData memory request
    ) internal view returns (bool isTrustedForwarder, bool active, bool signerMatch, address signer) {
        (bool isValid, address recovered) = _recoverForwardRequestSignerMem(request);

        return (
            _isTrustedByTargetLocal(request.to),
            request.deadline >= block.timestamp,
            isValid && recovered == request.from,
            recovered
        );
    }

    function _recoverForwardRequestSignerMem(
        ForwardRequestData memory request
    ) internal view virtual returns (bool, address) {
        (address recovered, ECDSA.RecoverError err, ) = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _FORWARD_REQUEST_TYPEHASH,
                    request.from,
                    request.to,
                    request.value,
                    request.gas,
                    nonces(request.from),
                    request.deadline,
                    keccak256(request.data)
                )
            )
        ).tryRecover(request.signature);

        return (err == ECDSA.RecoverError.NoError, recovered);
    }

    function _isTrustedByTargetLocal(address target) internal view returns (bool) {
        bytes memory encodedParams = abi.encodeCall(ERC2771Context.isTrustedForwarder, (address(this)));

        bool success;
        uint256 returnSize;
        uint256 returnValue;
        /// @solidity memory-safe-assembly
        assembly {
            // Perform the staticcal and save the result in the scratch space.
            // | Location  | Content  | Content (Hex)                                                      |
            // |-----------|----------|--------------------------------------------------------------------|
            // |           |          |                                                           result ↓ |
            // | 0x00:0x1F | selector | 0x0000000000000000000000000000000000000000000000000000000000000001 |
            success := staticcall(gas(), target, add(encodedParams, 0x20), mload(encodedParams), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        return success && returnSize >= 0x20 && returnValue > 0;
    }

    function _executeMem(
        ForwardRequestData memory request,
        bool requireValidRequest
    ) internal virtual returns (bool success) {
        (bool isTrustedForwarder, bool active, bool signerMatch, address signer) = _validateMem(request);

        // Need to explicitly specify if a revert is required since non-reverting is default for
        // batches and reversion is opt-in since it could be useful in some scenarios
        if (requireValidRequest) {
            if (!isTrustedForwarder) {
                revert ERC2771UntrustfulTarget(request.to, address(this));
            }

            if (!active) {
                revert ERC2771ForwarderExpiredRequest(request.deadline);
            }

            if (!signerMatch) {
                revert ERC2771ForwarderInvalidSigner(signer, request.from);
            }
        }

        // Ignore an invalid request because requireValidRequest = false
        if (isTrustedForwarder && signerMatch && active) {
            // Nonce should be used before the call to prevent reusing by reentrancy
            uint256 currentNonce = _useNonce(signer);

            uint256 reqGas = request.gas;
            address to = request.to;
            uint256 value = request.value;
            bytes memory data = abi.encodePacked(request.data, request.from);

            uint256 gasLeft;

            assembly {
                success := call(reqGas, to, value, add(data, 0x20), mload(data), 0, 0)
                gasLeft := gas()
            }

            _checkGasForwarded(gasLeft, request);

            emit ExecutedForwardRequest(signer, currentNonce, success);
        }
    }

    function _checkGasForwarded(uint256 gasLeft, ForwardRequestData memory request) internal pure {
        if (gasLeft < request.gas / 63) {
            /// @solidity memory-safe-assembly
            assembly {
                invalid()
            }
        }
    }
}
