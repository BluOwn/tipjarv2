// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./TipJarStructs.sol";

/**
 * @title TipJarAnalytics
 * @dev Library for handling tip history and analytics for the TipJar system
 */
library TipJarAnalytics {
    function getTipCount(TipJarStructs.Tip[] storage tips) internal view returns (uint256) {
        return tips.length;
    }

    function getRecentTips(TipJarStructs.Tip[] storage tips) 
        internal 
        view 
        returns (address[] memory senders, uint256[] memory amounts, string[] memory messages, uint256[] memory timestamps) 
    {
        uint256 length = tips.length;
        
        if (length == 0) {
            return (new address[](0), new uint256[](0), new string[](0), new uint256[](0));
        }
        
        uint256 resultLength = length > 10 ? 10 : length;
        
        senders = new address[](resultLength);
        amounts = new uint256[](resultLength);
        messages = new string[](resultLength);
        timestamps = new uint256[](resultLength);
        
        // Get the most recent tips (last elements in the array)
        for (uint256 i = 0; i < resultLength; i++) {
            uint256 index = length - resultLength + i;
            senders[i] = tips[index].sender;
            amounts[i] = tips[index].amount;
            messages[i] = tips[index].message;
            timestamps[i] = tips[index].timestamp;
        }
        
        return (senders, amounts, messages, timestamps);
    }

    function getTips(
        TipJarStructs.Tip[] storage tips,
        uint256 offset,
        uint256 limit
    ) internal view returns (
        address[] memory senders, 
        uint256[] memory amounts, 
        string[] memory messages, 
        uint256[] memory timestamps
    ) {
        uint256 length = tips.length;
        
        if (length == 0 || offset >= length) {
            return (new address[](0), new uint256[](0), new string[](0), new uint256[](0));
        }
        
        uint256 available = length - offset;
        uint256 resultLength = available < limit ? available : limit;
        
        senders = new address[](resultLength);
        amounts = new uint256[](resultLength);
        messages = new string[](resultLength);
        timestamps = new uint256[](resultLength);
        
        for (uint256 i = 0; i < resultLength; i++) {
            uint256 index = offset + i;
            senders[i] = tips[index].sender;
            amounts[i] = tips[index].amount;
            messages[i] = tips[index].message;
            timestamps[i] = tips[index].timestamp;
        }
        
        return (senders, amounts, messages, timestamps);
    }
}