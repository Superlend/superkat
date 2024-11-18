// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "forge-std/Test.sol";
import "forge-std/console.sol";

// Contracts
import {Invariants} from "./Invariants.t.sol";
import {Setup} from "./Setup.t.sol";

/*
 * Test suite that converts from  "fuzz tests" to foundry "unit tests"
 * The objective is to go from random values to hardcoded values that can be analyzed more easily
 */
contract CryticToFoundry is Invariants, Setup {
    CryticToFoundry Tester = this;

    modifier setup() override {
        _;
    }

    function setUp() public {
        // Deploy protocol contracts
        _setUp();

        // Deploy actors
        _setUpActors();

        // Initialize handler contracts
        _setUpHandlers();

        // Initialize hook contracts
        _setUpHooks();

        /// @dev fixes the actor to the first user
        actor = actors[USER1];

        vm.warp(101007);
    }

    /// @dev Needed in order for foundry to recognise the contract as a test, faster debugging
    function testAux() public {}

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                  POSTCONDITIONS REPLAY                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_redeemEchidna() public {
        this.addStrategy(50511606531911687419, 0);
        this.deposit(21, 0);
        this.rebalance(0, 0, 0);
        this.donateUnderlying(12, 0);
        this.harvest();
        this.mint(6254, 0);
        _delay(101007);
        this.setPerformanceFee(1012725796);
        this.simulateYieldAccrual(987897736, 0);
        this.redeem(5557, 0);
    }

    function test_updateInterestAccrued() public {
        this.donateUnderlying(1, 0);
        this.assert_ERC4626_WITHDRAW_INVARIANT_C();
        this.updateInterestAccrued();
    }

    function test_mintHSPOST_USER_D() public {
        this.donateUnderlying(39378, 0);
        this.assert_ERC4626_roundtrip_invariantE(0);
        _delay(31);
        this.mint(1, 0);
    }

    function test_assert_ERC4626_WITHDRAW_INVARIANT_C() public {
        this.donateUnderlying(1213962, 0);
        this.mint(1e22, 0);
        this.simulateYieldAccrual(1, 0);
        this.addStrategy(1, 0);
        this.toggleStrategyEmergencyStatus(0);
        this.toggleStrategyEmergencyStatus(0);
        this.setPerformanceFee(4);
        _delay(1);
        this.simulateYieldAccrual(250244936486004518, 0);
        this.assert_ERC4626_WITHDRAW_INVARIANT_C();
    }

    function test_toggleStrategyEmergencyStatus() public {
        Tester.simulateYieldAccrual(1, 0);
        Tester.addStrategy(1, 0);
        Tester.toggleStrategyEmergencyStatus(0);
        Tester.toggleStrategyEmergencyStatus(0);
    }

    function test_depositEchidna() public {
        this.donateUnderlying(1460294, 0);
        this.assert_ERC4626_roundtrip_invariantG(0);
        _delay(1);
        this.deposit(1, 0);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                               BROKEN POSTCONDITIONS REPLAY                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_assert_ERC4626_REDEEM_INVARIANT_C() public {
        //@audit-issue Issue 1: redeem(maxredeem) reverts -> allocated - uint120(withdrawAmount) underflows
        this.mint(20000, 0);
        this.addStrategy(1, 1);
        this.addStrategy(1, 0);
        _logStrategiesAllocation();
        this.adjustAllocationPoints(1007741998640599459404, 0);
        _logStrategiesAllocation();
        this.rebalance(0, 0, 0);
        _logStrategiesAllocation();
        this.simulateYieldAccrual(1, 1);
        this.rebalance(1, 0, 0);
        _logStrategiesAllocation();

        this.assert_ERC4626_REDEEM_INVARIANT_C();
    }

    function test_assert_ERC4626_roundtrip_invariantA() public {
        //@audit-issue . Issue 2: The invariant that should hold is: redeem(deposit(a)) > a
        // However in the poc below after depositing `a` and redeeming the amount of shares minted, assets redeemed is greater than `a`
        this.donateUnderlying(68, 0);
        this.assert_ERC4626_roundtrip_invariantA(0);

        _delay(35693);
        this.assert_ERC4626_roundtrip_invariantA(1);
    }

    function test_assert_ERC4626_roundtrip_invariantB() public {
        //@audit-issue . Issue 3: The invariant that should hold is: withdraw(a) >= deposit(a)
        // However in the poc below the shares minted after depositing `a` are bigger than the ones burned after withdrawing the amount of assets deposited
        this.donateUnderlying(597, 0);
        this.assert_ERC4626_roundtrip_invariantD(0);
        _delay(6100);
        this.assert_ERC4626_roundtrip_invariantB(2);
    }

    function test_assert_ERC4626_roundtrip_invariantE() public {
        //@audit-issue . Issue 4: The invariant that should hold is: withdraw(mint(s)) >= s
        // However in the poc below, while minting `s` shares and withdrawing the amount of assets deposited, shares burned is smaller than the initial amount of shares minted
        this.donateUnderlying(13153, 0);
        this.harvest();
        _delay(276);
        this.assert_ERC4626_roundtrip_invariantE(2);
    }

    function test_assert_ERC4626_roundtrip_invariantF() public {
        //@audit-issue . Issue 5: The invariant that should hold is: mint(s) >= redeem(s)
        // However in the poc below, while minting `s` shares and redeeming the same amount of shares minted, assets deposited is smaller than the amount of assets withdrawn
        this.donateUnderlying(2457159, 0);
        this.assert_ERC4626_WITHDRAW_INVARIANT_C();
        _delay(1);
        this.assert_ERC4626_roundtrip_invariantF(1);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     INVARIANTS REPLAY                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_echidna_INV_ASSETS_INVARIANTS_INV_ASSETS_A() public {
        // TODO check
        Tester.simulateYieldAccrual(1, 0);
        assert_INV_ASSETS_A();
        Tester.addStrategy(1, 0);
        assert_INV_ASSETS_A();
        Tester.toggleStrategyEmergencyStatus(0);
        assert_INV_ASSETS_A();
        Tester.toggleStrategyEmergencyStatus(0);
        assert_INV_ASSETS_A();
    }

    function test_INV_ASSETS_INVARIANTS_1() public {
        Tester.donateUnderlying(1 ether, 0);
        Tester.simulateYieldAccrual(1 ether, 0);
        Tester.addStrategy(1, 0);
        Tester.toggleStrategyEmergencyStatus(0);
        Tester.toggleStrategyEmergencyStatus(0);
        _delay(2 weeks);
        console.log(block.timestamp);
        echidna_INV_ASSETS_INVARIANTS();
    }

    function test_echidna_INV_BASE_INVARIANTS() public {
        this.donateUnderlying(3633281, 0);
        this.assert_ERC4626_WITHDRAW_INVARIANT_C();
        _delay(1);
        this.assert_ERC4626_roundtrip_invariantH(2);
        echidna_INV_BASE_INVARIANTS();
    }

    function test_echidna_INV_STRATEGIES_INVARIANTS() public {
        this.addStrategy(1, 0);
        this.toggleStrategyEmergencyStatus(0);
        echidna_INV_STRATEGIES_INVARIANTS();
    }

    function test_echidna_INV_BASE_INVARIANTS5() public {
        this.addStrategy(501757585924425152950, 2);
        this.mint(3, 0);
        this.rebalance(2, 0, 0);
        this.toggleStrategyEmergencyStatus(2);
        echidna_INV_ASSETS_INVARIANTS();
    }

    function test_echidna_INV_ASSETS_INVARIANTS2() public {
        Tester.addStrategy(50098849964587092381, 0);
        Tester.deposit(21, 0);
        Tester.rebalance(0, 0, 0);
        Tester.donateUnderlying(1, 0);
        Tester.redeem(21, 0);

        assert_INV_ASSETS_A();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 BROKEN INVARIANTS REPLAY                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Fast forward the time and set up an actor,
    /// @dev Use for ECHIDNA call-traces
    function _delay(uint256 _seconds) internal {
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Set up an actor
    function _setUpActor(address _origin) internal {
        actor = actors[_origin];
    }

    /// @notice Set up an actor and fast forward the time
    /// @dev Use for ECHIDNA call-traces
    function _setUpActorAndDelay(address _origin, uint256 _seconds) internal {
        actor = actors[_origin];
        vm.warp(block.timestamp + _seconds);
    }

    /// @notice Set up a specific block and actor
    function _setUpBlockAndActor(uint256 _block, address _user) internal {
        vm.roll(_block);
        actor = actors[_user];
    }

    /// @notice Set up a specific timestamp and actor
    function _setUpTimestampAndActor(uint256 _timestamp, address _user) internal {
        vm.warp(_timestamp);
        actor = actors[_user];
    }

    function _logStrategiesAllocation() internal {
        console.log("Strategy 0: ", eulerEulerEarnVault.getStrategy(strategies[0]).allocated);
        console.log("Strategy 1: ", eulerEulerEarnVault.getStrategy(strategies[1]).allocated);
        console.log("Strategy 2: ", eulerEulerEarnVault.getStrategy(strategies[2]).allocated);
    }
}
