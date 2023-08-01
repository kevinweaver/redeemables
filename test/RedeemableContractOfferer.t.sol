// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Solarray} from "solarray/Solarray.sol";
import {BaseOrderTest} from "./utils/BaseOrderTest.sol";
import {TestERC721} from "./utils/mocks/TestERC721.sol";
import {OfferItem, ConsiderationItem, SpentItem, AdvancedOrder, OrderParameters, CriteriaResolver, FulfillmentComponent} from "seaport-types/src/lib/ConsiderationStructs.sol";
// import {CriteriaResolutionErrors} from "seaport-types/src/interfaces/CriteriaResolutionErrors.sol";
import {ItemType, OrderType, Side} from "seaport-sol/src/SeaportEnums.sol";
import {OfferItemLib, ConsiderationItemLib, OrderParametersLib} from "seaport-sol/src/SeaportSol.sol";
import {RedeemableContractOfferer} from "../src/RedeemableContractOfferer.sol";
import {CampaignParams} from "../src/lib/RedeemableStructs.sol";
import {RedeemableErrorsAndEvents} from "../src/lib/RedeemableErrorsAndEvents.sol";
import {ERC721RedemptionMintable} from "../src/lib/ERC721RedemptionMintable.sol";
import {Merkle} from "../lib/murky/src/Merkle.sol";

contract TestRedeemableContractOfferer is
    BaseOrderTest,
    RedeemableErrorsAndEvents
{
    using OrderParametersLib for OrderParameters;

    error InvalidContractOrder();

    RedeemableContractOfferer offerer;
    TestERC721 redeemableToken;
    ERC721RedemptionMintable redemptionToken;
    CriteriaResolver[] criteriaResolvers;
    Merkle merkle = new Merkle();

    address constant _BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    function setUp() public override {
        super.setUp();
        offerer = new RedeemableContractOfferer(
            address(conduit),
            conduitKey,
            address(seaport)
        );
        redeemableToken = new TestERC721();
        redemptionToken = new ERC721RedemptionMintable(
            address(offerer),
            address(redeemableToken)
        );
        vm.label(address(redeemableToken), "redeemableToken");
        vm.label(address(redemptionToken), "redemptionToken");
    }

    function testUpdateParamsAndURI() public {
        CampaignParams memory params = CampaignParams({
            offer: new OfferItem[](0),
            consideration: new ConsiderationItem[](1),
            signer: address(0),
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1000),
            maxTotalRedemptions: 5,
            manager: address(this)
        });
        params.consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        uint256 campaignId = 1;
        vm.expectEmit(true, true, true, true);
        emit CampaignUpdated(campaignId, params, "http://test.com");

        offerer.updateCampaign(0, params, "http://test.com");

        (
            CampaignParams memory storedParams,
            string memory storedURI,
            uint256 totalRedemptions
        ) = offerer.getCampaign(campaignId);
        assertEq(storedParams.manager, address(this));
        assertEq(storedURI, "http://test.com");
        assertEq(totalRedemptions, 0);

        params.endTime = uint32(block.timestamp + 2000);

        vm.expectEmit(true, true, true, true);
        emit CampaignUpdated(campaignId, params, "http://test.com");

        offerer.updateCampaign(campaignId, params, "");

        (storedParams, storedURI, ) = offerer.getCampaign(campaignId);
        assertEq(storedParams.endTime, params.endTime);
        assertEq(storedParams.manager, address(this));
        assertEq(storedURI, "http://test.com");

        vm.expectEmit(true, true, true, true);
        emit CampaignUpdated(campaignId, params, "http://example.com");

        offerer.updateCampaign(campaignId, params, "http://example.com");

        (, storedURI, ) = offerer.getCampaign(campaignId);
        assertEq(storedURI, "http://example.com");

        vm.expectEmit(true, true, true, true);
        emit CampaignUpdated(campaignId, params, "http://foobar.com");

        offerer.updateCampaignURI(campaignId, "http://foobar.com");

        (, storedURI, ) = offerer.getCampaign(campaignId);
        assertEq(storedURI, "http://foobar.com");
    }

    function testRedeemWith721SafeTransferFrom() public {
        uint256 tokenId = 2;
        redeemableToken.mint(address(this), tokenId);

        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        CampaignParams memory params = CampaignParams({
            offer: offer,
            consideration: consideration,
            signer: address(0),
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1000),
            maxTotalRedemptions: 5,
            manager: address(this)
        });

        offerer.updateCampaign(0, params, "");

        OfferItem[] memory offerFromEvent = new OfferItem[](1);
        offerFromEvent[0] = OfferItem({
            itemType: ItemType.ERC721,
            token: address(redemptionToken),
            identifierOrCriteria: tokenId,
            startAmount: 1,
            endAmount: 1
        });

        ConsiderationItem[]
            memory considerationFromEvent = new ConsiderationItem[](1);
        considerationFromEvent[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: address(redeemableToken),
            identifierOrCriteria: tokenId,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        uint256 campaignId = 1;
        bytes32 redemptionHash = bytes32(0);
        bytes memory extraData = abi.encode(campaignId, redemptionHash);

        // TODO: validate OrderFulfilled event
        bytes memory data = abi.encode(campaignId, redemptionHash);
        redeemableToken.safeTransferFrom(
            address(this),
            address(offerer),
            tokenId,
            extraData
        );

        assertEq(redeemableToken.ownerOf(tokenId), _BURN_ADDRESS);
        assertEq(redemptionToken.ownerOf(tokenId), address(this));
    }

    function testRedeemWithSeaport() public {
        uint256 tokenId = 2;
        redeemableToken.mint(address(this), tokenId);
        redeemableToken.setApprovalForAll(address(conduit), true);

        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        {
            CampaignParams memory params = CampaignParams({
                offer: offer,
                consideration: consideration,
                signer: address(0),
                startTime: uint32(block.timestamp),
                endTime: uint32(block.timestamp + 1000),
                maxTotalRedemptions: 5,
                manager: address(this)
            });

            offerer.updateCampaign(0, params, "");
        }

        // uint256 campaignId = 1;
        // bytes32 redemptionHash = bytes32(0);

        {
            OfferItem[] memory offerFromEvent = new OfferItem[](1);
            offerFromEvent[0] = OfferItem({
                itemType: ItemType.ERC721,
                token: address(redemptionToken),
                identifierOrCriteria: tokenId,
                startAmount: 1,
                endAmount: 1
            });
            ConsiderationItem[]
                memory considerationFromEvent = new ConsiderationItem[](1);
            considerationFromEvent[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(redeemableToken),
                identifierOrCriteria: tokenId,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(_BURN_ADDRESS)
            });

            assertGt(
                uint256(consideration[0].itemType),
                uint256(considerationFromEvent[0].itemType)
            );

            bytes memory extraData = abi.encode(1, bytes32(0)); // campaignId, redemptionHash
            consideration[0].identifierOrCriteria = tokenId;

            // TODO: validate OrderFulfilled event
            OrderParameters memory parameters = OrderParametersLib
                .empty()
                .withOfferer(address(offerer))
                .withOrderType(OrderType.CONTRACT)
                .withConsideration(considerationFromEvent)
                .withOffer(offer)
                .withConduitKey(conduitKey)
                .withStartTime(block.timestamp)
                .withEndTime(block.timestamp + 1)
                .withTotalOriginalConsiderationItems(consideration.length);
            AdvancedOrder memory order = AdvancedOrder({
                parameters: parameters,
                numerator: 1,
                denominator: 1,
                signature: "",
                extraData: extraData
            });

            seaport.fulfillAdvancedOrder({
                advancedOrder: order,
                criteriaResolvers: criteriaResolvers,
                fulfillerConduitKey: conduitKey,
                recipient: address(0)
            });

            assertEq(redeemableToken.ownerOf(tokenId), _BURN_ADDRESS);
            assertEq(redemptionToken.ownerOf(tokenId), address(this));
        }
    }

    // TODO: add resolved tokenId to extradata

    function testRedeemWithCriteriaResolversViaSeaport() public {
        uint256 tokenId = 2;
        redeemableToken.mint(address(this), tokenId);
        redeemableToken.setApprovalForAll(address(conduit), true);

        CriteriaResolver[] memory resolvers = new CriteriaResolver[](1);

        // Create an array of hashed identifiers (0-4)
        // Only tokenIds 0-4 can be redeemed
        bytes32[] memory hashedIdentifiers = new bytes32[](5);
        for (uint256 i = 0; i < hashedIdentifiers.length; i++) {
            hashedIdentifiers[i] = keccak256(abi.encode(i));
        }
        bytes32 root = merkle.getRoot(hashedIdentifiers);

        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        // Contract offerer will only consider tokenIds 0-4
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: uint256(root),
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        {
            CampaignParams memory params = CampaignParams({
                offer: offer,
                consideration: consideration,
                signer: address(0),
                startTime: uint32(block.timestamp),
                endTime: uint32(block.timestamp + 1000),
                maxTotalRedemptions: 5,
                manager: address(this)
            });

            offerer.updateCampaign(0, params, "");
        }

        {
            OfferItem[] memory offerFromEvent = new OfferItem[](1);
            offerFromEvent[0] = OfferItem({
                itemType: ItemType.ERC721,
                token: address(redemptionToken),
                identifierOrCriteria: tokenId,
                startAmount: 1,
                endAmount: 1
            });
            ConsiderationItem[]
                memory considerationFromEvent = new ConsiderationItem[](1);
            considerationFromEvent[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(redeemableToken),
                identifierOrCriteria: tokenId,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(_BURN_ADDRESS)
            });

            assertGt(
                uint256(consideration[0].itemType),
                uint256(considerationFromEvent[0].itemType)
            );

            bytes memory extraData = abi.encode(1, bytes32(0)); // campaignId, redemptionHash

            OrderParameters memory parameters = OrderParametersLib
                .empty()
                .withOfferer(address(offerer))
                .withOrderType(OrderType.CONTRACT)
                .withConsideration(consideration)
                .withOffer(offer)
                .withConduitKey(conduitKey)
                .withStartTime(block.timestamp)
                .withEndTime(block.timestamp + 1)
                .withTotalOriginalConsiderationItems(consideration.length);
            AdvancedOrder memory order = AdvancedOrder({
                parameters: parameters,
                numerator: 1,
                denominator: 1,
                signature: "",
                extraData: extraData
            });

            resolvers[0] = CriteriaResolver({
                orderIndex: 0,
                side: Side.CONSIDERATION,
                index: 0,
                identifier: tokenId,
                criteriaProof: merkle.getProof(hashedIdentifiers, 2)
            });

            // TODO: validate OrderFulfilled event
            // vm.expectEmit(true, true, true, true);
            // emit OrderFulfilled();

            seaport.fulfillAdvancedOrder({
                advancedOrder: order,
                criteriaResolvers: resolvers,
                fulfillerConduitKey: conduitKey,
                recipient: address(0)
            });

            // TODO: failing because redemptionToken tokenId is merkle root
            assertEq(redeemableToken.ownerOf(tokenId), _BURN_ADDRESS);
            assertEq(redemptionToken.ownerOf(tokenId), address(this));
        }
    }

    function testRevertRedeemWithCriteriaResolversViaSeaport() public {
        uint256 tokenId = 7;
        redeemableToken.mint(address(this), tokenId);
        redeemableToken.setApprovalForAll(address(conduit), true);

        CriteriaResolver[] memory resolvers = new CriteriaResolver[](1);

        // Create an array of hashed identifiers (0-4)
        // Get the merkle root of the hashed identifiers to pass into updateCampaign
        // Only tokenIds 0-4 can be redeemed
        bytes32[] memory hashedIdentifiers = new bytes32[](5);
        for (uint256 i = 0; i < hashedIdentifiers.length; i++) {
            hashedIdentifiers[i] = keccak256(abi.encode(i));
        }
        bytes32 root = merkle.getRoot(hashedIdentifiers);

        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        // Contract offerer will only consider tokenIds 0-4
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: uint256(root),
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        {
            CampaignParams memory params = CampaignParams({
                offer: offer,
                consideration: consideration,
                signer: address(0),
                startTime: uint32(block.timestamp),
                endTime: uint32(block.timestamp + 1000),
                maxTotalRedemptions: 5,
                manager: address(this)
            });

            offerer.updateCampaign(0, params, "");
        }

        {
            // Hash identifiers 5 - 9 and create invalid merkle root
            // to pass into consideration
            for (uint256 i = 0; i < hashedIdentifiers.length; i++) {
                hashedIdentifiers[i] = keccak256(abi.encode(i + 5));
            }
            root = merkle.getRoot(hashedIdentifiers);
            consideration[0].identifierOrCriteria = uint256(root);

            OfferItem[] memory offerFromEvent = new OfferItem[](1);
            offerFromEvent[0] = OfferItem({
                itemType: ItemType.ERC721,
                token: address(redemptionToken),
                identifierOrCriteria: tokenId,
                startAmount: 1,
                endAmount: 1
            });
            ConsiderationItem[]
                memory considerationFromEvent = new ConsiderationItem[](1);
            considerationFromEvent[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(redeemableToken),
                identifierOrCriteria: tokenId,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(_BURN_ADDRESS)
            });

            assertGt(
                uint256(consideration[0].itemType),
                uint256(considerationFromEvent[0].itemType)
            );

            bytes memory extraData = abi.encode(1, bytes32(0)); // campaignId, redemptionHash

            OrderParameters memory parameters = OrderParametersLib
                .empty()
                .withOfferer(address(offerer))
                .withOrderType(OrderType.CONTRACT)
                .withConsideration(consideration)
                .withOffer(offer)
                .withConduitKey(conduitKey)
                .withStartTime(block.timestamp)
                .withEndTime(block.timestamp + 1)
                .withTotalOriginalConsiderationItems(consideration.length);
            AdvancedOrder memory order = AdvancedOrder({
                parameters: parameters,
                numerator: 1,
                denominator: 1,
                signature: "",
                extraData: extraData
            });

            resolvers[0] = CriteriaResolver({
                orderIndex: 0,
                side: Side.CONSIDERATION,
                index: 0,
                identifier: tokenId,
                criteriaProof: merkle.getProof(hashedIdentifiers, 2)
            });

            // TODO: validate OrderFulfilled event
            // vm.expectEmit(true, true, true, true);
            // emit OrderFulfilled();

            vm.expectRevert();
            seaport.fulfillAdvancedOrder({
                advancedOrder: order,
                criteriaResolvers: resolvers,
                fulfillerConduitKey: conduitKey,
                recipient: address(0)
            });
        }
    }

    function testRevertMaxTotalRedemptionsReached() public {
        redeemableToken.mint(address(this), 0);
        redeemableToken.mint(address(this), 1);
        redeemableToken.mint(address(this), 2);
        redeemableToken.setApprovalForAll(address(conduit), true);

        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        {
            CampaignParams memory params = CampaignParams({
                offer: offer,
                consideration: consideration,
                signer: address(0),
                startTime: uint32(block.timestamp),
                endTime: uint32(block.timestamp + 1000),
                maxTotalRedemptions: 2,
                manager: address(this)
            });

            offerer.updateCampaign(0, params, "");
        }

        {
            OfferItem[] memory offerFromEvent = new OfferItem[](1);
            offerFromEvent[0] = OfferItem({
                itemType: ItemType.ERC721,
                token: address(redemptionToken),
                identifierOrCriteria: 0,
                startAmount: 1,
                endAmount: 1
            });
            ConsiderationItem[]
                memory considerationFromEvent = new ConsiderationItem[](1);
            considerationFromEvent[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(redeemableToken),
                identifierOrCriteria: 0,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(_BURN_ADDRESS)
            });

            offerFromEvent[0] = OfferItem({
                itemType: ItemType.ERC721,
                token: address(redemptionToken),
                identifierOrCriteria: 1,
                startAmount: 1,
                endAmount: 1
            });

            considerationFromEvent[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(redeemableToken),
                identifierOrCriteria: 1,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(_BURN_ADDRESS)
            });

            assertGt(
                uint256(consideration[0].itemType),
                uint256(considerationFromEvent[0].itemType)
            );

            bytes memory extraData = abi.encode(1, bytes32(0)); // campaignId, redemptionHash

            considerationFromEvent[0].identifierOrCriteria = 0;

            OrderParameters memory parameters = OrderParametersLib
                .empty()
                .withOfferer(address(offerer))
                .withOrderType(OrderType.CONTRACT)
                .withConsideration(considerationFromEvent)
                .withOffer(offer)
                .withConduitKey(conduitKey)
                .withStartTime(block.timestamp)
                .withEndTime(block.timestamp + 1)
                .withTotalOriginalConsiderationItems(consideration.length);
            AdvancedOrder memory order = AdvancedOrder({
                parameters: parameters,
                numerator: 1,
                denominator: 1,
                signature: "",
                extraData: extraData
            });

            seaport.fulfillAdvancedOrder({
                advancedOrder: order,
                criteriaResolvers: criteriaResolvers,
                fulfillerConduitKey: conduitKey,
                recipient: address(0)
            });

            considerationFromEvent[0].identifierOrCriteria = 1;

            // vm.expectEmit(true, true, true, true);
            // emit Or(
            //     address(this),
            //     campaignId,
            //     ConsiderationItemLib.toSpentItemArray(considerationFromEvent),
            //     OfferItemLib.toSpentItemArray(offerFromEvent),
            //     redemptionHash
            // );

            seaport.fulfillAdvancedOrder({
                advancedOrder: order,
                criteriaResolvers: criteriaResolvers,
                fulfillerConduitKey: conduitKey,
                recipient: address(0)
            });

            considerationFromEvent[0].identifierOrCriteria = 2;

            // Should revert on the third redemption
            // The call to Seaport should revert with MaxTotalRedemptionsReached(3, 2)
            // vm.expectRevert(
            //     abi.encodeWithSelector(
            //         MaxTotalRedemptionsReached.selector,
            //         3,
            //         2
            //     )
            // );
            // vm.expectRevert(
            //     abi.encodeWithSelector(
            //         InvalidContractOrder.selector,
            //         (uint256(uint160(address(offerer))) << 96) +
            //             consideration.getContractOffererNonce(address(offerer))
            //     )
            // );
            seaport.fulfillAdvancedOrder({
                advancedOrder: order,
                criteriaResolvers: criteriaResolvers,
                fulfillerConduitKey: conduitKey,
                recipient: address(0)
            });

            assertEq(redeemableToken.ownerOf(0), _BURN_ADDRESS);
            assertEq(redeemableToken.ownerOf(1), _BURN_ADDRESS);
            assertEq(redemptionToken.ownerOf(0), address(this));
            assertEq(redemptionToken.ownerOf(1), address(this));
        }
    }

    function testRevertConsiderationItemRecipientCannotBeZeroAddress() public {
        uint256 tokenId = 2;
        redeemableToken.mint(address(this), tokenId);
        redeemableToken.setApprovalForAll(address(conduit), true);

        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(0))
        });

        {
            CampaignParams memory params = CampaignParams({
                offer: offer,
                consideration: consideration,
                signer: address(0),
                startTime: uint32(block.timestamp),
                endTime: uint32(block.timestamp + 1000),
                maxTotalRedemptions: 5,
                manager: address(this)
            });

            vm.expectRevert(
                abi.encodeWithSelector(
                    ConsiderationItemRecipientCannotBeZeroAddress.selector
                )
            );
            offerer.updateCampaign(0, params, "");
        }
    }

    // TODO: burn 2 to redeem 1, burn 1 to redeem 2
    // TODO: burn 1, send weth to third address, also redeem trait
    // TODO: mock erc20 to third address or burn
    // TODO: make MockErc20RedemptionMintable with mintRedemption
    // TODO: burn nft and send erc20 to third address, get nft and erc20
    // TODO: mintRedemption should return tokenIds array
    // TODO: then add dynamic traits
    // TODO: by EOW, have dynamic traits demo

    function testBurn2Redeem1WithSeaport() public {
        // Set the two tokenIds to be burned
        uint256 burnTokenId0 = 2;
        uint256 burnTokenId1 = 3;

        // Mint two redeemableTokens of tokenId burnTokenId0 and burnTokenId1 to the test contract
        redeemableToken.mint(address(this), burnTokenId0);
        redeemableToken.mint(address(this), burnTokenId1);

        // Approve the conduit to transfer the redeemableTokens on behalf of the test contract
        redeemableToken.setApprovalForAll(address(conduit), true);

        // Create a single-item OfferItem array with the redemption token the caller will receive
        OfferItem[] memory offer = new OfferItem[](1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        // Create a single-item ConsiderationItem array and require the caller to burn two redeemableTokens (of any tokenId)
        ConsiderationItem[] memory consideration = new ConsiderationItem[](2);
        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        consideration[1] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        // Create the CampaignParams with the offer and consideration from above.
        {
            CampaignParams memory params = CampaignParams({
                offer: offer,
                consideration: consideration,
                signer: address(0),
                startTime: uint32(block.timestamp),
                endTime: uint32(block.timestamp + 1000),
                maxTotalRedemptions: 5,
                manager: address(this)
            });

            // Call updateCampaign on the offerer and pass in the CampaignParams
            offerer.updateCampaign(0, params, "");
        }

        // uint256 campaignId = 1;
        // bytes32 redemptionHash = bytes32(0);

        {
            // Create the offer we expect to be emitted in the event
            OfferItem[] memory offerFromEvent = new OfferItem[](1);
            offerFromEvent[0] = OfferItem({
                itemType: ItemType.ERC721,
                token: address(redemptionToken),
                identifierOrCriteria: burnTokenId0,
                startAmount: 1,
                endAmount: 1
            });

            // Create the consideration we expect to be emitted in the event
            ConsiderationItem[]
                memory considerationFromEvent = new ConsiderationItem[](2);
            considerationFromEvent[0] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(redeemableToken),
                identifierOrCriteria: burnTokenId0,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(_BURN_ADDRESS)
            });

            considerationFromEvent[1] = ConsiderationItem({
                itemType: ItemType.ERC721,
                token: address(redeemableToken),
                identifierOrCriteria: burnTokenId1,
                startAmount: 1,
                endAmount: 1,
                recipient: payable(_BURN_ADDRESS)
            });

            // Check that the consideration passed into updateCampaign has itemType ERC721_WITH_CRITERIA
            assertEq(uint256(consideration[0].itemType), 4);

            // Check that the consideration emitted in the event has itemType ERC721
            assertEq(uint256(considerationFromEvent[0].itemType), 2);
            assertEq(uint256(considerationFromEvent[1].itemType), 2);

            // Create the extraData to be passed into fulfillAdvancedOrder
            bytes memory extraData = abi.encode(1, bytes32(0)); // campaignId, redemptionHash

            // TODO: validate OrderFulfilled event

            // Create the OrderParameters to be passed into fulfillAdvancedOrder
            OrderParameters memory parameters = OrderParametersLib
                .empty()
                .withOfferer(address(offerer))
                .withOrderType(OrderType.CONTRACT)
                .withConsideration(considerationFromEvent)
                .withOffer(offer)
                .withConduitKey(conduitKey)
                .withStartTime(block.timestamp)
                .withEndTime(block.timestamp + 1)
                .withTotalOriginalConsiderationItems(
                    considerationFromEvent.length
                );

            // Create the AdvancedOrder to be passed into fulfillAdvancedOrder
            AdvancedOrder memory order = AdvancedOrder({
                parameters: parameters,
                numerator: 1,
                denominator: 1,
                signature: "",
                extraData: extraData
            });

            // Call fulfillAdvancedOrder
            seaport.fulfillAdvancedOrder({
                advancedOrder: order,
                criteriaResolvers: criteriaResolvers,
                fulfillerConduitKey: conduitKey,
                recipient: address(0)
            });

            // Check that the two redeemable tokens have been burned
            assertEq(redeemableToken.ownerOf(burnTokenId0), _BURN_ADDRESS);
            assertEq(redeemableToken.ownerOf(burnTokenId1), _BURN_ADDRESS);

            // Check that the redemption token has been minted to the test contract
            assertEq(redemptionToken.ownerOf(burnTokenId0), address(this));
        }
    }

    function xtestRedeemMultipleWithSeaport() public {
        uint256 tokenId;
        redeemableToken.setApprovalForAll(address(conduit), true);

        AdvancedOrder[] memory orders = new AdvancedOrder[](5);
        OfferItem[] memory offer = new OfferItem[](1);
        ConsiderationItem[] memory consideration = new ConsiderationItem[](1);

        uint256 campaignId = 1;
        bytes32 redemptionHash = bytes32(0);

        offer[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        consideration[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        OrderParameters memory parameters = OrderParametersLib
            .empty()
            .withOfferer(address(offerer))
            .withOrderType(OrderType.CONTRACT)
            .withConsideration(consideration)
            .withOffer(offer)
            .withStartTime(block.timestamp)
            .withEndTime(block.timestamp + 1)
            .withTotalOriginalConsiderationItems(1);

        for (uint256 i; i < 5; i++) {
            tokenId = i;
            redeemableToken.mint(address(this), tokenId);

            bytes memory extraData = abi.encode(campaignId, redemptionHash);
            AdvancedOrder memory order = AdvancedOrder({
                parameters: parameters,
                numerator: 1,
                denominator: 1,
                signature: "",
                extraData: extraData
            });

            orders[i] = order;
        }

        CampaignParams memory params = CampaignParams({
            offer: offer,
            consideration: consideration,
            signer: address(0),
            startTime: uint32(block.timestamp),
            endTime: uint32(block.timestamp + 1000),
            maxTotalRedemptions: 5,
            manager: address(this)
        });

        offerer.updateCampaign(0, params, "");

        OfferItem[] memory offerFromEvent = new OfferItem[](1);
        offerFromEvent[0] = OfferItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redemptionToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1
        });

        ConsiderationItem[]
            memory considerationFromEvent = new ConsiderationItem[](1);
        considerationFromEvent[0] = ConsiderationItem({
            itemType: ItemType.ERC721_WITH_CRITERIA,
            token: address(redeemableToken),
            identifierOrCriteria: 0,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(_BURN_ADDRESS)
        });

        (
            FulfillmentComponent[][] memory offerFulfillmentComponents,
            FulfillmentComponent[][] memory considerationFulfillmentComponents
        ) = fulfill.getNaiveFulfillmentComponents(orders);

        seaport.fulfillAvailableAdvancedOrders({
            advancedOrders: orders,
            criteriaResolvers: criteriaResolvers,
            offerFulfillments: offerFulfillmentComponents,
            considerationFulfillments: considerationFulfillmentComponents,
            fulfillerConduitKey: conduitKey,
            recipient: address(0),
            maximumFulfilled: 10
        });

        for (uint256 i; i < 5; i++) {
            tokenId = i;
            assertEq(redeemableToken.ownerOf(tokenId), _BURN_ADDRESS);
            assertEq(redemptionToken.ownerOf(tokenId), address(this));
        }
    }
}
