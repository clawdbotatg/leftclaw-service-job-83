// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC2981 } from "@openzeppelin/contracts/token/common/ERC2981.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Ai Punks
 * @notice ERC-721 collection (max 10,000) with $CLAWD-balance-gated free mints.
 *
 * @dev Pricing oracle: Option B (owner-settable USD-per-CLAWD price).
 *
 *      Why Option B and not a Uniswap V3 TWAP?
 *      - The 0.3% $CLAWD/WETH pool on Base has zero active liquidity.
 *      - The 1% pool has liquidity but is a community-token pool with thin
 *        depth and only one provider. A TWAP on a single concentrated-LP
 *        pool is cheap to push and easy to grief — every griefer can mint
 *        free NFTs by inflating their on-paper $CLAWD balance.
 *      - This contract therefore exposes `setClawdUsdPrice` (onlyOwner) and
 *        defaults `clawdUsdPrice` to 0. While `clawdUsdPrice == 0`, no free
 *        mints are awarded — the collection mints normally at 0.069 ETH.
 *        The owner sets the price post-deploy from a venue they trust.
 *
 *      Free-mint rules:
 *        usdValue       = (clawdBalance * clawdUsdPrice) / 1e36
 *                         (clawdBalance is 1e18 scaled, clawdUsdPrice is
 *                          1e18 scaled USD-per-token, both divided out)
 *        eligibleFree   = min(20, usdValue / 1000)
 *        remaining      = eligibleFree - usedFreeMints[msg.sender]   (>= 0)
 *        freeUsed       = min(quantity, remaining,
 *                              MAX_FREE_MINTS - totalFreeMintsUsed)
 *        paidQty        = quantity - freeUsed
 *        require msg.value >= paidQty * mintPrice
 *        any excess ETH is refunded to msg.sender
 *
 *      Sybil disclosure (M-2):
 *        The 20 per-wallet free-mint cap is enforced but is NOT
 *        Sybil-resistant — a CLAWD holder can transfer the same balance
 *        between fresh wallets to claim 20 free mints from each. To bound
 *        the worst case, this contract additionally enforces a global
 *        free-mint supply cap, `MAX_FREE_MINTS` (20% of supply by default).
 *        Once that cap is reached, all subsequent mints are paid mints
 *        regardless of CLAWD balance.
 */
contract AiPunks is ERC721, ERC2981, Ownable, ReentrancyGuard {
    using Strings for uint256;

    // ------------------------------------------------------------------ //
    // Constants                                                          //
    // ------------------------------------------------------------------ //

    /// @notice Total cap on minted token IDs.
    uint256 public constant MAX_SUPPLY = 10_000;

    /// @notice Max free mints any single wallet can ever claim.
    uint256 public constant MAX_FREE_PER_WALLET = 20;

    /// @notice Global cap on free mints across all wallets (20% of MAX_SUPPLY).
    ///         Bounds the Sybil bypass of the per-wallet cap (see contract NatSpec, M-2).
    uint256 public constant MAX_FREE_MINTS = 2_000;

    /// @notice USD threshold (no decimals) per free mint — $1,000 of $CLAWD
    ///         gets you one free mint, $2,000 gets two, etc., up to 20.
    uint256 public constant USD_PER_FREE_MINT = 1_000;

    /// @notice $CLAWD ERC20 token (Base mainnet).
    IERC20 public constant CLAWD = IERC20(0x9f86dB9fc6f7c9408e8Fda3Ff8ce4e78ac7a6b07);

    /// @notice Royalty BPS (5%).
    uint96 public constant ROYALTY_BPS = 500;

    /// @notice Hard ceiling on `clawdUsdPrice` — 1 USD per whole CLAWD (1e18-scaled).
    ///         Prevents owner fat-fingers / overflows in `freeMintsEligible` (M-3 / L-1).
    uint256 public constant MAX_CLAWD_USD_PRICE = 1e18;

    /// @notice Per-tx cap on `quantity` for `mint()` — prevents accidental
    ///         block-gas-limit reverts and makes the limit explicit to the dApp (L-2).
    uint256 public constant MAX_BATCH = 50;

    /// @notice Hard ceiling on royalty BPS — 10% (1000 / 10000) (L-4).
    uint96 public constant MAX_ROYALTY_BPS = 1_000;

    // ------------------------------------------------------------------ //
    // State                                                              //
    // ------------------------------------------------------------------ //

    /// @notice Price (in wei) per token for paid mints. Default 0.069 ETH.
    uint256 public mintPrice = 0.069 ether;

    /// @notice USD price of one whole $CLAWD token, scaled to 1e18.
    ///         e.g. $0.001 == 1e15. Zero disables free mints.
    uint256 public clawdUsdPrice;

    /// @notice Running token-id counter — also the number of tokens minted.
    uint256 public totalMinted;

    /// @notice Total free mints consumed across all wallets. Capped by MAX_FREE_MINTS.
    uint256 public totalFreeMintsUsed;

    /// @notice Free mints already consumed per wallet.
    mapping(address => uint256) public usedFreeMints;

    /// @notice Base URI for tokenURI; owner-settable post-deploy.
    string private _baseTokenURI;

    // ------------------------------------------------------------------ //
    // Events                                                             //
    // ------------------------------------------------------------------ //

    event Minted(address indexed buyer, uint256 quantity, uint256 freeUsed, uint256 paid);
    event BaseURIUpdated(string newURI);
    event MintPriceUpdated(uint256 newPrice);
    event ClawdUsdPriceUpdated(uint256 newPrice);
    event RoyaltyUpdated(address indexed receiver, uint96 feeNumerator);

    // ------------------------------------------------------------------ //
    // Errors                                                             //
    // ------------------------------------------------------------------ //

    error ZeroQuantity();
    error MaxSupplyExceeded();
    error Underpaid(uint256 required, uint256 sent);
    error RefundFailed();
    error WithdrawFailed();
    error BatchTooLarge();
    error PriceTooHigh();
    error RoyaltyTooHigh();
    error ZeroAddress();

    // ------------------------------------------------------------------ //
    // Constructor                                                        //
    // ------------------------------------------------------------------ //

    /**
     * @param initialOwner Address that owns the contract, receives royalties,
     *                     and can withdraw mint proceeds.
     * @param baseURI_     Initial baseURI (use a placeholder; update later).
     */
    constructor(address initialOwner, string memory baseURI_) ERC721("Ai Punks", "AIPUNK") Ownable(initialOwner) {
        _baseTokenURI = baseURI_;
        _setDefaultRoyalty(initialOwner, ROYALTY_BPS);
    }

    // ------------------------------------------------------------------ //
    // Mint                                                               //
    // ------------------------------------------------------------------ //

    /**
     * @notice Mint `quantity` tokens to `msg.sender`. Free mints (if any) are
     *         applied first, then any remaining tokens cost `mintPrice` each.
     *         Excess ETH is refunded.
     * @dev    Free mints are clamped by both per-wallet (`MAX_FREE_PER_WALLET`)
     *         and global (`MAX_FREE_MINTS`) caps. Once `totalFreeMintsUsed`
     *         reaches `MAX_FREE_MINTS`, all subsequent mints are paid mints.
     *         Per-tx `quantity` is capped at `MAX_BATCH` to keep gas bounded.
     */
    function mint(uint256 quantity) external payable nonReentrant {
        if (quantity == 0) revert ZeroQuantity();
        if (quantity > MAX_BATCH) revert BatchTooLarge();
        if (totalMinted + quantity > MAX_SUPPLY) revert MaxSupplyExceeded();

        // Free-mint accounting (per-wallet and global cap).
        uint256 eligible = freeMintsEligible(msg.sender);
        uint256 used = usedFreeMints[msg.sender];
        uint256 walletRemaining = eligible > used ? eligible - used : 0;
        uint256 globalRemaining = MAX_FREE_MINTS - totalFreeMintsUsed; // bounded above by MAX_FREE_MINTS
        uint256 remaining = walletRemaining < globalRemaining ? walletRemaining : globalRemaining;
        uint256 freeUsed = quantity < remaining ? quantity : remaining;
        uint256 paidQty = quantity - freeUsed;
        uint256 required = paidQty * mintPrice;

        if (msg.value < required) revert Underpaid(required, msg.value);

        if (freeUsed > 0) {
            usedFreeMints[msg.sender] = used + freeUsed;
            totalFreeMintsUsed += freeUsed;
        }

        // Effects: mint tokens, ids start at 1.
        uint256 startId = totalMinted;
        totalMinted = startId + quantity;
        for (uint256 i = 0; i < quantity; ++i) {
            _safeMint(msg.sender, startId + i + 1);
        }

        emit Minted(msg.sender, quantity, freeUsed, required);

        // Refund any excess (placed last to satisfy CEI; nonReentrant guards anyway).
        // L-3 note: contract-receivers whose receive() reverts must send msg.value
        // exactly equal to `required` — otherwise refund will revert RefundFailed.
        uint256 refund = msg.value - required;
        if (refund > 0) {
            (bool ok,) = payable(msg.sender).call{ value: refund }("");
            if (!ok) revert RefundFailed();
        }
    }

    // ------------------------------------------------------------------ //
    // View helpers                                                       //
    // ------------------------------------------------------------------ //

    /**
     * @notice How many free mints `account` is *ever* eligible for given
     *         their current $CLAWD balance and the current `clawdUsdPrice`.
     *         Capped at `MAX_FREE_PER_WALLET` (20).
     * @dev    USD value truncates cents (intentional, I-4): a holder with
     *         $999.99 of CLAWD gets 0 free mints, $1,000.00 gets 1, etc.
     *         `clawdUsdPrice` is bounded by `MAX_CLAWD_USD_PRICE`, which keeps
     *         `clawdBal * price` well below 2^256 for any plausible CLAWD
     *         balance (CLAWD total supply is ~1e29, so worst case is ~1e47).
     */
    function freeMintsEligible(address account) public view returns (uint256) {
        uint256 price = clawdUsdPrice;
        if (price == 0) return 0;

        uint256 clawdBal = CLAWD.balanceOf(account);
        // clawdBal is 1e18, price is 1e18 USD-per-token; product is 1e36.
        // Divide by 1e36 to get whole-USD value (truncating cents).
        uint256 usdValue = (clawdBal * price) / 1e36;
        uint256 eligible = usdValue / USD_PER_FREE_MINT;
        return eligible > MAX_FREE_PER_WALLET ? MAX_FREE_PER_WALLET : eligible;
    }

    /**
     * @notice Free mints `account` can still claim right now (eligible minus
     *         used, further clamped by global remaining).
     */
    function freeMintsRemaining(address account) external view returns (uint256) {
        uint256 eligible = freeMintsEligible(account);
        uint256 used = usedFreeMints[account];
        uint256 walletRemaining = eligible > used ? eligible - used : 0;
        uint256 globalRemaining = MAX_FREE_MINTS - totalFreeMintsUsed;
        return walletRemaining < globalRemaining ? walletRemaining : globalRemaining;
    }

    /**
     * @notice Total free mints still available across the whole collection
     *         (`MAX_FREE_MINTS` - `totalFreeMintsUsed`). Surfaced for the dApp
     *         so it can disable the free-mint UI when the global pool is empty.
     */
    function freeMintsRemainingGlobal() external view returns (uint256) {
        return MAX_FREE_MINTS - totalFreeMintsUsed;
    }

    // ------------------------------------------------------------------ //
    // Owner controls                                                     //
    // ------------------------------------------------------------------ //

    function setBaseURI(string calldata newURI) external onlyOwner {
        _baseTokenURI = newURI;
        emit BaseURIUpdated(newURI);
    }

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    /**
     * @notice Set the USD price of $CLAWD, scaled to 1e18.
     *         e.g. for $0.001 USD-per-CLAWD pass `1e15`.
     *         Setting 0 disables free mints (default at deploy).
     * @dev    Bounded by `MAX_CLAWD_USD_PRICE` (1 USD per whole CLAWD,
     *         1e18-scaled). Anything above that is rejected — a community
     *         token priced at $1.00 each is already absurd; this prevents
     *         fat-finger / overflow scenarios in `freeMintsEligible` (M-3).
     */
    function setClawdUsdPrice(uint256 newPrice) external onlyOwner {
        if (newPrice > MAX_CLAWD_USD_PRICE) revert PriceTooHigh();
        clawdUsdPrice = newPrice;
        emit ClawdUsdPriceUpdated(newPrice);
    }

    /**
     * @notice Update the ERC2981 default royalty.
     * @dev    Capped at `MAX_ROYALTY_BPS` (10%) to keep the collection
     *         compatible with major marketplaces (L-4). Reverts on
     *         zero-address receiver.
     */
    function setRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        if (feeNumerator > MAX_ROYALTY_BPS) revert RoyaltyTooHigh();
        _setDefaultRoyalty(receiver, feeNumerator);
        emit RoyaltyUpdated(receiver, feeNumerator);
    }

    /**
     * @notice Withdraw the contract's ETH balance to the current owner.
     * @dev    Push-payment to `owner()` via low-level call. If `owner()` is
     *         ever transferred to a contract that cannot receive ETH (no
     *         payable `receive`/`fallback`), `withdraw()` will revert with
     *         `WithdrawFailed` until the client `transferOwnership` to a
     *         payable wallet again. Funds are never permanently lost (M-1).
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        (bool ok,) = payable(owner()).call{ value: bal }("");
        if (!ok) revert WithdrawFailed();
    }

    // ------------------------------------------------------------------ //
    // Metadata                                                           //
    // ------------------------------------------------------------------ //

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @notice tokenURI returns `<baseURI><id>.json`. Reverts on unminted ids.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory base = _baseURI();
        return bytes(base).length == 0 ? "" : string(abi.encodePacked(base, tokenId.toString(), ".json"));
    }

    // ------------------------------------------------------------------ //
    // ERC165                                                             //
    // ------------------------------------------------------------------ //

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
