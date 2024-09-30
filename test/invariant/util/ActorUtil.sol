// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Test} from "forge-std/Test.sol";

contract ActorUtil is Test {
    address eulerEulerEarnVault;

    /// @dev actor[0] will always be a manager address that have access to all EulerEarn roles.
    address[] public actors;
    /// @dev using a mapping to detect fee receiver, just for cleaner and expected test results.
    mapping(address => bool) public isFeeReceiver;

    constructor(address _eulerEulerEarnVault) {
        eulerEulerEarnVault = _eulerEulerEarnVault;
    }

    function includeActor(address _actor) external {
        actors.push(_actor);

        vm.prank(_actor);
        IVotes(eulerEulerEarnVault).delegate(_actor);
    }

    function initiateExactActorCall(uint256 _actorIndex, address _target, bytes memory _calldata)
        external
        returns (address, bool, bytes memory)
    {
        address currentActor = _getExactActor(_actorIndex);

        vm.prank(currentActor);
        (bool success, bytes memory returnData) = address(_target).call(_calldata);

        return (currentActor, success, returnData);
    }

    function initiateActorCall(uint256 _actorIndexSeed, address _target, bytes memory _calldata)
        external
        returns (address, bool, bytes memory)
    {
        address currentActor = _getActor(_actorIndexSeed);

        vm.prank(currentActor);
        (bool success, bytes memory returnData) = address(_target).call(_calldata);

        return (currentActor, success, returnData);
    }

    function setAsFeeReceiver(address _feeReceiver) external {
        isFeeReceiver[_feeReceiver] = true;
    }

    function fetchActor(uint256 _actorIndexSeed) external view returns (address, uint256) {
        uint256 randomActorIndex = bound(_actorIndexSeed, 0, actors.length - 1);
        address randomActor = actors[randomActorIndex];

        return (randomActor, randomActorIndex);
    }

    function getActors() external view returns (address[] memory) {
        address[] memory actorsList = new address[](actors.length);

        for (uint256 i; i < actors.length; i++) {
            actorsList[i] = actors[i];
        }

        return actorsList;
    }

    function _getActor(uint256 _actorIndexSeed) internal view returns (address) {
        return actors[bound(_actorIndexSeed, 0, actors.length - 1)];
    }

    function _getExactActor(uint256 _actorIndex) internal view returns (address) {
        return actors[_actorIndex];
    }
}
