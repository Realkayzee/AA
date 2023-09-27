// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.20;

import "../interfaces/IDiamondCut.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";
import { Diamond } from "../Diamond.sol";
import { IERC173 } from "../interfaces/IERC173.sol";


/**
 * Pride Factory for smart account
 * A UserOperation "initcode" holds the address of the factory, and a method call to create account
 * The Factory's createAccount account returns a targetted account address
 * Te targetted account address is deterministic and can be call even before the account is created
 */

contract PrideSmartAccountFactory {
    event UpgradedAccount(address prideSmartAccount);

    using CREATE3 for bytes32;

    address public immutable diamondCutFacet;
    enum FacetCutAction {Add, Replace, Remove}
    // Add=0, Replace=1, Reemove=2

    constructor(address _diamondCutFacet) {
        diamondCutFacet = _diamondCutFacet;
    }

    /**
     * Create an account and return its address.
     * return address if the account is already deployed with the inputed salt
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     */
    function createAccount(address owner, bytes32 salt, IDiamondCut.FacetCut[] calldata cut, address diamondInit) public returns (address account) {
        address deployedAddress = salt.getDeployed();
        if(deployedAddress == address(0)) {
            account = salt.deploy(
                abi.encodePacked(
                    type(Diamond).creationCode,
                    abi.encode(
                        owner,
                        diamondCutFacet
                    )
                ),
                0
            );

            bytes memory functionCall = abi.encodeWithSignature("init()");
            IDiamondCut(account).diamondCut(cut, diamondInit, functionCall);
        } else {
            account = deployedAddress;
        }
    }

    /**
     * calculate deterministic address as it would be returned by createAccount(owner, salt)
     * use the same create2 used in createAccount to compute address
     */
    function getAddress(address owner, bytes32 salt) public view returns (address addr) {
        bytes32 bytecodeHash = keccak256(
            abi.encodePacked(
                type(Diamond).creationCode,
                abi.encode(
                    owner,
                    diamondCutFacet
                )
            )
        );
        assembly {
            // cache the free memroy pointer.
            let ptr := mload(0x40)
            // store bytecodeHash to location ptr + 0x40
            mstore(add(ptr, 0x40), bytecodeHash)
            // store salt to location ptr + 0x20
            mstore(add(ptr, 0x20), salt)
            // store owner to ptr location
            mstore(ptr, owner)
            // store prefix
            mstore8(add(ptr, 0x0b), 0xff)

            /**
             * The memory appear as
             *  |-------------------|---------------------------------------------------------------------------|
             *  |                   |                                                        ↓ ptr + 64         |
             *  | bytecodeHash      |                                      ↓ ptr + 32        CCCCCCCCCCCCC...CC |
             *  | salt              | ↓ ptr       ↓ ptr + 11                BBBBBBBBBBBBB...BB                  |
             *  | owner             | 000000...0000AAAAAAAAAAAAAAAAAAA...AA                                     |
             *  | 0xFF              |            FF                                                             |
             *  |-------------------|---------------------------------------------------------------------------|
             *  | memory            | 000000...00FFAAAAAAAAAAAAAAAAAAA...AABBBBBBBBBBBBB...BBCCCCCCCCCCCCC...CC |
             *  | keccak(start, 85) |            ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑ |
             */
            addr := keccak256(add(ptr, 0x0b), 0x55)
        }
    }
}