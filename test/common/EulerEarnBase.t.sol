// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/interfaces/IHookTarget.sol";
// contracts
import "evk-test/unit/evault/EVaultTestBase.t.sol";
import {EulerEarn, IEulerEarn, Shared} from "../../src/EulerEarn.sol";
import {EulerEarnVault} from "../../src/module/EulerEarnVault.sol";
import {Hooks, HooksModule} from "../../src/module/Hooks.sol";
import {Rewards} from "../../src/module/Rewards.sol";
import {Fee} from "../../src/module/Fee.sol";
import {WithdrawalQueue} from "../../src/module/WithdrawalQueue.sol";
import {EulerEarnFactory} from "../../src/EulerEarnFactory.sol";
import {Strategy} from "../../src/module/Strategy.sol";
// libs
import {ErrorsLib} from "../../src/lib/ErrorsLib.sol";
import {EventsLib} from "../../src/lib/EventsLib.sol";
import {AmountCapLib as AggAmountCapLib, AmountCap as AggAmountCap} from "../../src/lib/AmountCapLib.sol";
import {ConstantsLib} from "../../src/lib/ConstantsLib.sol";

contract EulerEarnBase is EVaultTestBase {
    using AggAmountCapLib for AggAmountCap;

    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    address deployer;
    address user1;
    address user2;
    address manager;

    Shared.IntegrationsParams integrationsParams;
    IEulerEarn.DeploymentParams deploymentParams;

    // core modules
    EulerEarnVault eulerEarnVaultModule;
    Rewards rewardsModule;
    Hooks hooksModule;
    Fee feeModule;
    Strategy strategyModule;
    WithdrawalQueue withdrawalQueueModule;

    address eulerEarnImpl;
    EulerEarnFactory eulerEulerEarnVaultFactory;
    EulerEarn eulerEulerEarnVault;

    function setUp() public virtual override {
        super.setUp();

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");
        manager = makeAddr("Manager");

        vm.startPrank(deployer);
        integrationsParams = Shared.IntegrationsParams({
            evc: address(evc),
            balanceTracker: address(0),
            permit2: permit2,
            isHarvestCoolDownCheckOn: true
        });

        eulerEarnVaultModule = new EulerEarnVault(integrationsParams);
        rewardsModule = new Rewards(integrationsParams);
        hooksModule = new Hooks(integrationsParams);
        feeModule = new Fee(integrationsParams);
        strategyModule = new Strategy(integrationsParams);
        withdrawalQueueModule = new WithdrawalQueue(integrationsParams);

        deploymentParams = IEulerEarn.DeploymentParams({
            eulerEarnVaultModule: address(eulerEarnVaultModule),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModule),
            strategyModule: address(strategyModule),
            withdrawalQueueModule: address(withdrawalQueueModule)
        });
        eulerEarnImpl = address(new EulerEarn(integrationsParams, deploymentParams));

        eulerEulerEarnVaultFactory = new EulerEarnFactory(eulerEarnImpl);
        eulerEulerEarnVault = EulerEarn(
            eulerEulerEarnVaultFactory.deployEulerEarn(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS, 2 weeks
            )
        );

        // grant admin roles to deployer
        eulerEulerEarnVault.grantRole(ConstantsLib.GUARDIAN_ADMIN, deployer);
        eulerEulerEarnVault.grantRole(ConstantsLib.STRATEGY_OPERATOR_ADMIN, deployer);
        eulerEulerEarnVault.grantRole(ConstantsLib.EULER_EARN_MANAGER_ADMIN, deployer);
        eulerEulerEarnVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER_ADMIN, deployer);
        eulerEulerEarnVault.grantRole(ConstantsLib.REBALANCER_ADMIN, deployer);

        // grant roles to manager
        eulerEulerEarnVault.grantRole(ConstantsLib.GUARDIAN, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.STRATEGY_OPERATOR, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.EULER_EARN_MANAGER, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.REBALANCER, manager);

        vm.stopPrank();

        vm.label(address(eulerEulerEarnVaultFactory), "eulerEulerEarnVaultFactory");
        vm.label(address(eulerEulerEarnVault), "eulerEulerEarnVault");
        vm.label(eulerEulerEarnVault.rewardsModule(), "rewardsModule");
        vm.label(eulerEulerEarnVault.hooksModule(), "hooksModule");
        vm.label(eulerEulerEarnVault.feeModule(), "feeModule");
        vm.label(eulerEulerEarnVault.strategyModule(), "strategyModule");
        vm.label(address(assetTST), "assetTST");
    }

    function testInitialParams() public view {
        IEulerEarn.Strategy memory cashReserve = eulerEulerEarnVault.getStrategy(address(0));

        assertEq(cashReserve.allocated, 0);
        assertEq(cashReserve.allocationPoints, CASH_RESERVE_ALLOCATION_POINTS);
        assertEq(cashReserve.status == IEulerEarn.StrategyStatus.Active, true);

        assertEq(eulerEulerEarnVault.getRoleAdmin(ConstantsLib.GUARDIAN), ConstantsLib.GUARDIAN_ADMIN);
        assertEq(eulerEulerEarnVault.getRoleAdmin(ConstantsLib.STRATEGY_OPERATOR), ConstantsLib.STRATEGY_OPERATOR_ADMIN);
        assertEq(
            eulerEulerEarnVault.getRoleAdmin(ConstantsLib.EULER_EARN_MANAGER), ConstantsLib.EULER_EARN_MANAGER_ADMIN
        );
        assertEq(
            eulerEulerEarnVault.getRoleAdmin(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER),
            ConstantsLib.WITHDRAWAL_QUEUE_MANAGER_ADMIN
        );
        assertEq(eulerEulerEarnVault.getRoleAdmin(ConstantsLib.REBALANCER), ConstantsLib.REBALANCER_ADMIN);

        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.GUARDIAN_ADMIN, deployer));
        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.STRATEGY_OPERATOR_ADMIN, deployer));
        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.EULER_EARN_MANAGER_ADMIN, deployer));
        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER_ADMIN, deployer));
        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.REBALANCER_ADMIN, deployer));

        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.GUARDIAN, manager));
        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.STRATEGY_OPERATOR, manager));
        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.EULER_EARN_MANAGER, manager));
        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER, manager));
        assertTrue(eulerEulerEarnVault.hasRole(ConstantsLib.REBALANCER, manager));

        assertEq(eulerEulerEarnVaultFactory.getEulerEarnVaultsListLength(), 1);
        address[] memory eulerEarnVaultsList = eulerEulerEarnVaultFactory.getEulerEarnVaultsListSlice(0, 1);
        assertEq(eulerEarnVaultsList.length, 1);
        assertEq(address(eulerEarnVaultsList[0]), address(eulerEulerEarnVault));
        assertEq(eulerEulerEarnVault.decimals(), assetTST.decimals());

        assertEq(address(eulerEulerEarnVault.EVC()), address(evc));
        assertEq(eulerEulerEarnVault.eulerEarnVaultModule(), deploymentParams.eulerEarnVaultModule);
        assertEq(eulerEulerEarnVault.rewardsModule(), deploymentParams.rewardsModule);
        assertEq(eulerEulerEarnVault.hooksModule(), deploymentParams.hooksModule);
        assertEq(eulerEulerEarnVault.feeModule(), deploymentParams.feeModule);
        assertEq(eulerEulerEarnVault.strategyModule(), deploymentParams.strategyModule);
        assertEq(eulerEulerEarnVault.withdrawalQueueModule(), deploymentParams.withdrawalQueueModule);
        assertEq(eulerEulerEarnVault.isCheckingHarvestCoolDown(), true);
        assertEq(eulerEulerEarnVault.permit2Address(), permit2);

        assertTrue(eulerEulerEarnVaultFactory.isValidDeployment(address(eulerEulerEarnVault)));
        assertFalse(eulerEulerEarnVaultFactory.isValidDeployment(address(assetTST)));
    }

    function testDeployEulerEarnWithInvalidInitialCashAllocationPoints() public {
        vm.expectRevert(ErrorsLib.InitialAllocationPointsZero.selector);
        eulerEulerEarnVaultFactory.deployEulerEarn(address(assetTST), "assetTST_Agg", "assetTST_Agg", 0, 2 weeks);
    }

    function testDeployEulerEarnWithInvalidSmearingPeriod() public {
        vm.expectRevert(ErrorsLib.InvalidSmearingPeriod.selector);
        eulerEulerEarnVaultFactory.deployEulerEarn(address(assetTST), "assetTST_Agg", "assetTST_Agg", 100, 2);
    }

    function _addStrategy(address from, address strategy, uint256 allocationPoints) internal {
        vm.prank(from);
        eulerEulerEarnVault.addStrategy(strategy, allocationPoints);
    }

    function _getWithdrawalQueue() internal view returns (address[] memory) {
        return eulerEulerEarnVault.withdrawalQueue();
    }

    function _getWithdrawalQueueLength() internal view returns (uint256) {
        address[] memory withdrawalQueueArray = eulerEulerEarnVault.withdrawalQueue();
        return withdrawalQueueArray.length;
    }
}
