// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TipJarBase.sol";
import "./TipJarSocial.sol";
import "./TipJarAnalytics.sol";
import "./TipJarStructs.sol";

/**
 * @title TipJar - Upgradeable Version
 * @dev A contract where users can create tip jars and receive tips with a 1% fee going to the creator
 * @notice Official website: https://montip.xyz/
 * @notice This is now an upgradeable contract using UUPS proxy pattern
 */
contract TipJar is TipJarBase {
    using TipJarSocial for mapping(string => string);
    using TipJarAnalytics for TipJarStructs.Tip[];
    
    function addSocialLink(string memory key, string memory value) public {
        string memory username = ownerToUsername[msg.sender];
        require(bytes(username).length > 0, "You don't have a jar");
        
        TipJarSocial.addSocialLink(
            jars[username].socialLinks,
            jars[username].socialLinkKeys,
            username,
            key,
            value,
            MAX_SOCIAL_LINKS,
            MAX_SOCIAL_VALUE_LENGTH
        );
    }
    
    function removeSocialLink(string memory key) public {
        string memory username = ownerToUsername[msg.sender];
        require(bytes(username).length > 0, "You don't have a jar");
        
        TipJarSocial.removeSocialLink(
            jars[username].socialLinks,
            jars[username].socialLinkKeys,
            username,
            key
        );
    }
    
    function getSocialLinks(string memory username) 
        public 
        view 
        jarExists(username) 
        returns (string[] memory keys, string[] memory values) 
    {
        return TipJarSocial.getSocialLinks(
            jars[username].socialLinks,
            jars[username].socialLinkKeys
        );
    }

    function getTipCount(string memory username) 
        public 
        view 
        jarExists(username) 
        returns (uint256) 
    {
        return TipJarAnalytics.getTipCount(tipHistory[username]);
    }

    function getRecentTips(string memory username) 
        public 
        view 
        jarExists(username) 
        returns (address[] memory, uint256[] memory, string[] memory, uint256[] memory) 
    {
        return TipJarAnalytics.getRecentTips(tipHistory[username]);
    }

    function getTips(string memory username, uint256 offset, uint256 limit)
        public
        view
        jarExists(username)
        returns (address[] memory, uint256[] memory, string[] memory, uint256[] memory)
    {
        return TipJarAnalytics.getTips(tipHistory[username], offset, limit);
    }
    
    function getAllTips(string memory username)
        public
        view
        jarExists(username)
        returns (address[] memory senders, uint256[] memory amounts, string[] memory messages, uint256[] memory timestamps)
    {
        return TipJarAnalytics.getTips(tipHistory[username], 0, tipHistory[username].length);
    }

    function getRawJarData(uint256 limit, uint256 offset)
        public
        view
        returns (string[] memory usernames, uint256[] memory totals)
    {
        // Count total existing jars
        uint256 existingJarsCount = 0;
        for (uint256 i = 0; i < allUsernames.length; i++) {
            string memory username = allUsernames[i];
            if (jars[username].exists) {
                existingJarsCount++;
            }
        }
        
        // Check if offset is valid
        if (offset >= existingJarsCount) {
            return (new string[](0), new uint256[](0));
        }
        
        // Calculate how many results to return
        uint256 resultCount = existingJarsCount - offset;
        if (resultCount > limit) {
            resultCount = limit;
        }
        
        // Create arrays for results
        usernames = new string[](resultCount);
        totals = new uint256[](resultCount);
        
        // Collect data without sorting
        uint256 currentIndex = 0;
        uint256 skippedCount = 0;
        
        for (uint256 i = 0; i < allUsernames.length && currentIndex < resultCount; i++) {
            string memory username = allUsernames[i];
            if (jars[username].exists) {
                if (skippedCount >= offset) {
                    usernames[currentIndex] = username;
                    totals[currentIndex] = jars[username].totalReceived;
                    currentIndex++;
                } else {
                    skippedCount++;
                }
            }
        }
        
        return (usernames, totals);
    }

    // NEW: Batch operations for admin
    function adminDeleteMultipleJars(string[] memory usernames) public onlyOwner {
        for (uint256 i = 0; i < usernames.length; i++) {
            if (jars[usernames[i]].exists) {
                address jarOwner = jars[usernames[i]].owner;
                _performJarDeletion(jarOwner, usernames[i]);
                emit JarDeletedByAdmin(msg.sender, jarOwner, usernames[i]);
            }
        }
    }

    // NEW: Get all jars by owner (for admin panel)
    function getJarsByOwner(address owner) public view returns (string memory username, bool exists) {
        username = ownerToUsername[owner];
        exists = bytes(username).length > 0 && jars[username].exists;
    }

    // NEW: Get total statistics
    function getTotalStats() public view returns (
        uint256 totalJars,
        uint256 totalTips,
        uint256 totalVolume
    ) {
        totalJars = allUsernames.length;
        totalTips = 0;
        totalVolume = 0;
        
        for (uint256 i = 0; i < allUsernames.length; i++) {
            string memory username = allUsernames[i];
            if (jars[username].exists) {
                totalTips += tipHistory[username].length;
                totalVolume += jars[username].totalReceived;
            }
        }
        
        return (totalJars, totalTips, totalVolume);
    }

    // NEW: Emergency pause all jars (admin only)
    function emergencyPauseAllJars() public onlyOwner {
        pause();
    }

    // NEW: Override getVersion to show current version
    function getVersion() public pure override returns (string memory) {
        return "v1.1.0-upgradeable";
    }
}