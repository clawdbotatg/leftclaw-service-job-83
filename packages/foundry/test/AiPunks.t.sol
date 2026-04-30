// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { AiPunks } from "../contracts/AiPunks.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal ERC20 stand-in for $CLAWD. Lives at the same hardcoded address
///      via `vm.etch` so AiPunks reads from it via its `IERC20 public constant`.
contract MockClawd {
    mapping(address => uint256) private _balances;

    function setBalance(address to, uint256 amount) external {
        _balances[to] = amount;
    }

    function balanceOf(address who) external view returns (uint256) {
        return _balances[who];
    }
}

/// @dev Contract that rejects ETH — used for L-3 / M-1 negative paths.
contract RejectEth {
    AiPunks public immutable punks;

    constructor(AiPunks _punks) payable {
        punks = _punks;
    }

    function tryMint(uint256 quantity) external payable {
        punks.mint{ value: msg.value }(quantity);
    }

    function callWithdraw() external {
        punks.withdraw();
    }

    // No receive / fallback => any ETH transfer reverts.
}

contract AiPunksTest is Test {
    AiPunks internal punks;
    MockClawd internal clawd;

    address internal constant CLAWD_ADDR = 0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07;

    address internal owner = address(0xA11CE);
    address internal alice = address(0xA1);
    address internal bob = address(0xB0B);

    function setUp() public {
        // Deploy a MockClawd, then etch its bytecode at the hardcoded CLAWD address.
        MockClawd impl = new MockClawd();
        vm.etch(CLAWD_ADDR, address(impl).code);
        clawd = MockClawd(CLAWD_ADDR);

        punks = new AiPunks(owner, "ipfs://base/");
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // --------------------------------------------------------------------- //
    // Constants / setters                                                   //
    // --------------------------------------------------------------------- //

    function test_constants() public view {
        assertEq(punks.MAX_SUPPLY(), 10_000);
        assertEq(punks.MAX_FREE_PER_WALLET(), 20);
        assertEq(punks.MAX_FREE_MINTS(), 2_000);
        assertEq(punks.MAX_BATCH(), 50);
        assertEq(punks.MAX_CLAWD_USD_PRICE(), 1e18);
        assertEq(punks.mintPrice(), 0.069 ether);
        assertEq(punks.owner(), owner);
        assertEq(punks.freeMintsRemainingGlobal(), 2_000);
    }

    function test_setMintPrice_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        punks.setMintPrice(1 ether);

        vm.prank(owner);
        punks.setMintPrice(1 ether);
        assertEq(punks.mintPrice(), 1 ether);
    }

    function test_setClawdUsdPrice_onlyOwner_andBound() public {
        vm.prank(alice);
        vm.expectRevert();
        punks.setClawdUsdPrice(1e15);

        vm.prank(owner);
        punks.setClawdUsdPrice(1e15);
        assertEq(punks.clawdUsdPrice(), 1e15);

        // Bound: anything > 1e18 reverts.
        vm.prank(owner);
        vm.expectRevert(AiPunks.PriceTooHigh.selector);
        punks.setClawdUsdPrice(1e18 + 1);

        // Boundary: exactly 1e18 is OK.
        vm.prank(owner);
        punks.setClawdUsdPrice(1e18);
        assertEq(punks.clawdUsdPrice(), 1e18);
    }

    function test_setRoyalty_capAndZeroAddress() public {
        // Zero address rejected.
        vm.prank(owner);
        vm.expectRevert(AiPunks.ZeroAddress.selector);
        punks.setRoyalty(address(0), 500);

        // Above 10% rejected.
        vm.prank(owner);
        vm.expectRevert(AiPunks.RoyaltyTooHigh.selector);
        punks.setRoyalty(owner, 1_001);

        // Within cap accepted.
        vm.prank(owner);
        punks.setRoyalty(alice, 1_000);

        (address recv, uint256 amt) = punks.royaltyInfo(1, 10_000);
        assertEq(recv, alice);
        assertEq(amt, 1_000);
    }

    function test_setBaseURI_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        punks.setBaseURI("ipfs://new/");

        vm.prank(owner);
        punks.setBaseURI("ipfs://new/");
    }

    // --------------------------------------------------------------------- //
    // Paid mint                                                             //
    // --------------------------------------------------------------------- //

    function test_paidMint_happyPath() public {
        // No CLAWD price set => no free mints.
        vm.prank(alice);
        punks.mint{ value: 0.069 ether * 3 }(3);
        assertEq(punks.balanceOf(alice), 3);
        assertEq(punks.totalMinted(), 3);
        assertEq(punks.usedFreeMints(alice), 0);
        assertEq(punks.totalFreeMintsUsed(), 0);
        // Token IDs are 1..3.
        assertEq(punks.ownerOf(1), alice);
        assertEq(punks.ownerOf(3), alice);
    }

    function test_paidMint_underpaidReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AiPunks.Underpaid.selector, 0.069 ether * 2, 0.069 ether));
        punks.mint{ value: 0.069 ether }(2);
    }

    function test_paidMint_refundsExcess() public {
        uint256 balBefore = alice.balance;
        vm.prank(alice);
        punks.mint{ value: 1 ether }(1);
        // Spent: 0.069 ETH. Refunded: 0.931 ETH.
        assertEq(balBefore - alice.balance, 0.069 ether);
    }

    function test_zeroQuantityReverts() public {
        vm.prank(alice);
        vm.expectRevert(AiPunks.ZeroQuantity.selector);
        punks.mint{ value: 0 }(0);
    }

    function test_batchTooLargeReverts() public {
        vm.prank(alice);
        vm.expectRevert(AiPunks.BatchTooLarge.selector);
        punks.mint{ value: 0.069 ether * 51 }(51);

        // 50 is the boundary — should pass.
        vm.deal(alice, 100 ether);
        vm.prank(alice);
        punks.mint{ value: 0.069 ether * 50 }(50);
        assertEq(punks.balanceOf(alice), 50);
    }

    // --------------------------------------------------------------------- //
    // Free mint                                                             //
    // --------------------------------------------------------------------- //

    function test_freeMintsEligible_zeroPrice() public {
        clawd.setBalance(alice, 1_000_000e18); // huge CLAWD balance
        // clawdUsdPrice = 0 => 0 free mints.
        assertEq(punks.freeMintsEligible(alice), 0);
    }

    function test_freeMintsEligible_thresholds() public {
        // price = $0.001 per CLAWD = 1e15 (1e18-scaled).
        vm.prank(owner);
        punks.setClawdUsdPrice(1e15);

        // 999,999 CLAWD * $0.001 = $999.99 => 0 free mints.
        clawd.setBalance(alice, 999_999e18);
        assertEq(punks.freeMintsEligible(alice), 0);

        // 1,000,000 CLAWD * $0.001 = $1000 => 1 free mint.
        clawd.setBalance(alice, 1_000_000e18);
        assertEq(punks.freeMintsEligible(alice), 1);

        // 5,000,000 CLAWD * $0.001 = $5000 => 5 free mints.
        clawd.setBalance(alice, 5_000_000e18);
        assertEq(punks.freeMintsEligible(alice), 5);

        // 100,000,000 CLAWD * $0.001 = $100,000 => clamped to 20.
        clawd.setBalance(alice, 100_000_000e18);
        assertEq(punks.freeMintsEligible(alice), 20);
    }

    function test_freeMint_happyPath() public {
        vm.prank(owner);
        punks.setClawdUsdPrice(1e15); // $0.001 per CLAWD
        clawd.setBalance(alice, 5_000_000e18); // 5 free mints

        vm.prank(alice);
        punks.mint{ value: 0 }(3);

        assertEq(punks.balanceOf(alice), 3);
        assertEq(punks.usedFreeMints(alice), 3);
        assertEq(punks.totalFreeMintsUsed(), 3);
        assertEq(punks.freeMintsRemaining(alice), 2);
    }

    function test_mixedFreePaid() public {
        vm.prank(owner);
        punks.setClawdUsdPrice(1e15);
        clawd.setBalance(alice, 2_000_000e18); // 2 free mints

        // Mint 5 total: 2 free + 3 paid.
        vm.prank(alice);
        punks.mint{ value: 0.069 ether * 3 }(5);

        assertEq(punks.balanceOf(alice), 5);
        assertEq(punks.usedFreeMints(alice), 2);
        assertEq(punks.totalFreeMintsUsed(), 2);
        assertEq(punks.freeMintsRemaining(alice), 0);
    }

    function test_globalFreeMintCap() public {
        vm.prank(owner);
        punks.setClawdUsdPrice(1e15);
        // Give 100 wallets enough CLAWD for 20 free mints each.
        // 20 × 100 = 2000 = MAX_FREE_MINTS — the next wallet must pay.
        for (uint160 i = 1; i <= 100; i++) {
            address w = address(uint160(0x10000) + i);
            clawd.setBalance(w, 100_000_000e18); // 20 free
            vm.deal(w, 0);
            vm.prank(w);
            punks.mint{ value: 0 }(20);
        }
        assertEq(punks.totalFreeMintsUsed(), 2_000);
        assertEq(punks.freeMintsRemainingGlobal(), 0);

        // Wallet 101 has CLAWD but global cap reached — must pay full price.
        address w101 = address(uint160(0x10000) + 101);
        clawd.setBalance(w101, 100_000_000e18);
        vm.deal(w101, 1 ether);

        // Calling with 0 ETH for 1 mint reverts (no free mints left globally).
        vm.prank(w101);
        vm.expectRevert(abi.encodeWithSelector(AiPunks.Underpaid.selector, 0.069 ether, 0));
        punks.mint{ value: 0 }(1);

        // Paying full price works.
        vm.prank(w101);
        punks.mint{ value: 0.069 ether }(1);
        assertEq(punks.balanceOf(w101), 1);
        assertEq(punks.usedFreeMints(w101), 0);
        assertEq(punks.totalFreeMintsUsed(), 2_000);
    }

    function test_maxSupplyExhaustion() public {
        // Use a paid path + max batch to walk to the cap quickly.
        // 10_000 / 50 = 200 batches.
        for (uint256 i = 0; i < 200; i++) {
            address w = address(uint160(0x20000 + i));
            vm.deal(w, 4 ether);
            vm.prank(w);
            punks.mint{ value: 0.069 ether * 50 }(50);
        }
        assertEq(punks.totalMinted(), 10_000);

        address late = address(0xDEAD);
        vm.deal(late, 1 ether);
        vm.prank(late);
        vm.expectRevert(AiPunks.MaxSupplyExceeded.selector);
        punks.mint{ value: 0.069 ether }(1);
    }

    // --------------------------------------------------------------------- //
    // Withdraw                                                              //
    // --------------------------------------------------------------------- //

    function test_withdraw_onlyOwner() public {
        vm.prank(alice);
        punks.mint{ value: 0.069 ether }(1);

        vm.prank(alice);
        vm.expectRevert();
        punks.withdraw();

        uint256 ownerBefore = owner.balance;
        vm.prank(owner);
        punks.withdraw();
        assertEq(owner.balance - ownerBefore, 0.069 ether);
        assertEq(address(punks).balance, 0);
    }

    function test_withdraw_revertsForNonPayableOwner() public {
        // Move ownership to a contract that rejects ETH.
        RejectEth rj = new RejectEth(punks);
        vm.prank(owner);
        punks.transferOwnership(address(rj));

        // Mint to load some ETH into the contract.
        vm.prank(alice);
        punks.mint{ value: 0.069 ether }(1);

        // Owner contract calls withdraw — push fails => WithdrawFailed.
        vm.expectRevert(AiPunks.WithdrawFailed.selector);
        rj.callWithdraw();

        // Funds are not lost — transfer ownership back to a payable wallet.
        vm.prank(address(rj));
        punks.transferOwnership(owner);
        vm.prank(owner);
        punks.withdraw();
        assertEq(address(punks).balance, 0);
    }

    // --------------------------------------------------------------------- //
    // Token URI / metadata                                                  //
    // --------------------------------------------------------------------- //

    function test_tokenURI() public {
        vm.prank(alice);
        punks.mint{ value: 0.069 ether }(1);
        assertEq(punks.tokenURI(1), "ipfs://base/1.json");
    }

    function test_tokenURI_unminted_reverts() public {
        vm.expectRevert();
        punks.tokenURI(999);
    }

    function test_supportsInterface_2981() public view {
        // ERC2981 interface id.
        assertTrue(punks.supportsInterface(0x2a55205a));
        // ERC721
        assertTrue(punks.supportsInterface(0x80ac58cd));
    }
}
