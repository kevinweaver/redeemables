// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {CampaignParams} from "./RedeemableStructs.sol";

interface RedeemableErrorsAndEvents {
    /// Configuration errors
    error NotManager();
    error InvalidTime();
    error NoConsiderationItems();
    error ConsiderationItemRecipientCannotBeZeroAddress();

    /// Redemption errors
    error InvalidCampaignId();
    error InvalidCaller(address caller);
    error NotActive(uint256 currentTimestamp, uint256 startTime, uint256 endTime);
    error MaxRedemptionsReached(uint256 total, uint256 max);
    error MaxTotalRedemptionsReached(uint256 total, uint256 max);
    error RedeemMismatchedLengths();
    error TraitValueUnchanged(bytes32 traitKey, bytes32 value);
    error InvalidConsiderationLength(uint256 got, uint256 want);
    error InvalidConsiderationItem(address got, address want);
    error InvalidOfferLength(uint256 got, uint256 want);
    error ConsiderationRecipientNotFound(address token);
    error RedemptionValuesAreImmutable();

    /// Events
    event CampaignUpdated(uint256 indexed campaignId, CampaignParams params, string uri);
    event Redemption(
        address indexed by, uint256 indexed campaignId, SpentItem[] spent, SpentItem[] received, bytes32 redemptionHash
    );
}
