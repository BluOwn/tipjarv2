// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TipJarSocial
 * @dev A library to handle social links for the TipJar system
 */
library TipJarSocial {
    event SocialLinkAdded(string indexed username, string key, string value);
    event SocialLinkRemoved(string indexed username, string key);

    function addSocialLink(
        mapping(string => string) storage socialLinks,
        string[] storage socialLinkKeys,
        string memory username,
        string memory key,
        string memory value,
        uint256 maxLinks,
        uint256 maxValueLength
    ) internal returns (bool) {
        require(
            keccak256(bytes(key)) == keccak256(bytes("twitter")) || 
            keccak256(bytes(key)) == keccak256(bytes("website")) ||
            keccak256(bytes(key)) == keccak256(bytes("discord")) ||
            keccak256(bytes(key)) == keccak256(bytes("telegram")) ||
            keccak256(bytes(key)) == keccak256(bytes("instagram")) ||
            keccak256(bytes(key)) == keccak256(bytes("youtube")),
            "Invalid social link type"
        );
        require(bytes(value).length <= maxValueLength, "Value too long");
        
        // Check if key already exists
        bool keyExists = false;
        for (uint256 i = 0; i < socialLinkKeys.length; i++) {
            if (keccak256(bytes(socialLinkKeys[i])) == keccak256(bytes(key))) {
                keyExists = true;
                break;
            }
        }
        
        // Add key to the list if it doesn't exist
        if (!keyExists) {
            require(socialLinkKeys.length < maxLinks, "Too many social links");
            socialLinkKeys.push(key);
        }
        
        // Set or update the value
        socialLinks[key] = value;
        
        emit SocialLinkAdded(username, key, value);
        return true;
    }
    
    function removeSocialLink(
        mapping(string => string) storage socialLinks,
        string[] storage socialLinkKeys,
        string memory username,
        string memory key
    ) internal returns (bool) {
        // Check if key exists and remove it
        for (uint256 i = 0; i < socialLinkKeys.length; i++) {
            if (keccak256(bytes(socialLinkKeys[i])) == keccak256(bytes(key))) {
                // Remove the key by replacing it with the last element and popping
                socialLinkKeys[i] = socialLinkKeys[socialLinkKeys.length - 1];
                socialLinkKeys.pop();
                
                // Delete the mapping entry
                delete socialLinks[key];
                
                emit SocialLinkRemoved(username, key);
                return true;
            }
        }
        
        revert("Social link not found");
    }
    
    function getSocialLinks(
        mapping(string => string) storage socialLinks,
        string[] storage socialLinkKeys
    ) internal view returns (string[] memory keys, string[] memory values) {
        uint256 linkCount = socialLinkKeys.length;
        
        keys = new string[](linkCount);
        values = new string[](linkCount);
        
        for (uint256 i = 0; i < linkCount; i++) {
            keys[i] = socialLinkKeys[i];
            values[i] = socialLinks[socialLinkKeys[i]];
        }
        
        return (keys, values);
    }
}