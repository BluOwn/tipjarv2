// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title TipJarStructs
 * @dev Shared structs for TipJar contracts
 */
library TipJarStructs {
    struct Tip {
        address sender;
        uint256 amount;
        string message;
        uint256 timestamp;
    }

    struct JarInfo {
        address owner;
        string username;
        string description;
        uint256 totalReceived;
        bool exists;
        mapping(string => string) socialLinks;
        string[] socialLinkKeys;
    }
}