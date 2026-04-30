// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { AiPunks } from "../contracts/AiPunks.sol";

/**
 * @notice Deploy script for AiPunks
 * @dev Deploys the AiPunks ERC-721 with the LeftClaw job client as initial owner.
 *      Note: the file name stays `DeployYourContract.s.sol` so that the SE-2
 *      `yarn deploy` flow continues to find it from `Deploy.s.sol`.
 */
contract DeployYourContract is ScaffoldETHDeploy {
    /// @notice LeftClaw job #83 client — receives ownership and royalties.
    address internal constant CLIENT_OWNER = 0x68B8dD3d7d5CEdB72B40c4cF3152a175990D4599;

    /// @notice Placeholder baseURI; the owner can update this post-deploy via setBaseURI().
    string internal constant INITIAL_BASE_URI = "ipfs://placeholder/";

    function run() external ScaffoldEthDeployerRunner {
        new AiPunks(CLIENT_OWNER, INITIAL_BASE_URI);
    }
}
