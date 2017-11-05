pragma solidity ^0.4.15;

import "./LikeCoin.sol";

contract ContributorPool {
    LikeCoin public like;
    // avoid using 0 as fields in proposals are by default initialized to 0
    uint64 minApprovedId = 1;
    uint64 nextId = 1;

    uint8 public threshold;
    uint256 public lockDuration;

    uint256 lockedCoin;
    mapping (uint64 => uint256) giveUnlockTime;
    address[] public owners;
    mapping (address => uint256) ownerIndex;

    struct Proposal {
        uint64 id;
        address proposer;
        uint8 confirmNeeded;
        uint256 confirmedTable;
    }
    mapping (uint64 => Proposal) proposals;
    event ProposalConfirmation(uint64 indexed _id, address _confirmer);
    event ProposalExecution(uint64 indexed _id, address _executer);

    struct GiveInfo {
        uint64 id;
        address to;
        uint256 value;
    }
    mapping (uint64 => GiveInfo) giveInfo;
    event GiveProposal(uint64 indexed _id, address _proposer, address _to, uint256 _value);
    event Claimed(uint64 indexed _id);

    struct SetOwnersInfo {
        uint64 id;
        uint8 newThreshold;
        address[] newOwners;
    }
    mapping (uint64 => SetOwnersInfo) setOwnersInfo;
    event SetOwnersProposal(uint64 indexed _id, address _proposer, address[] _newOwners, uint8 _newThreshold);

    function ContributorPool(address _likeAddr, address[] _owners, uint256 _lockDuration,
                             uint8 _threshold) public {
        require(_owners.length < 256);
        require(_owners.length > 0);
        require(_threshold > 0);
        like = LikeCoin(_likeAddr);
        for (uint8 i = 0; i < _owners.length; ++i) {
            owners.push(_owners[i]);
            ownerIndex[_owners[i]] = uint256(1) << i;
        }
        lockDuration = _lockDuration;
        threshold = _threshold;
        lockedCoin = 0;
    }

    function ownersCount() public constant returns (uint) {
        return owners.length;
    }

    function getRemainingLikeCoins() public constant returns (uint256) {
        return (like.balanceOf(address(this)) - lockedCoin);
    }

    function getUnlockTime(uint64 id) public constant returns (uint256) {
        return giveUnlockTime[id];
    }

    function _nextId() internal returns (uint64 id) {
        id = nextId;
        nextId += 1;
        return id;
    }

    function proposeGive(address _to, uint256 _value) public {
        require(ownerIndex[msg.sender] != 0);
        require(_value > 0);
        uint64 id = _nextId();
        proposals[id] = Proposal(id, msg.sender, threshold, 0);
        giveInfo[id] = GiveInfo(id, _to, _value);
        GiveProposal(id, msg.sender, _to, _value);
    }

    function proposeSetOwners(address[] _newOwners, uint8 _newThreshold) public {
        require(ownerIndex[msg.sender] != 0);
        require(_newOwners.length < 256);
        require(_newOwners.length > 0);
        require(_newThreshold > 0);
        uint64 id = _nextId();
        proposals[id] = Proposal(id, msg.sender, threshold, 0);
        setOwnersInfo[id] = SetOwnersInfo(id, _newThreshold, _newOwners);
        SetOwnersProposal(id, msg.sender, _newOwners, _newThreshold);
    }

    function confirmProposal(uint64 id) public {
        require(id >= minApprovedId);
        require(proposals[id].id == id);
        require(proposals[id].confirmNeeded > 0);
        uint256 index = ownerIndex[msg.sender];
        require(index != 0);
        require((proposals[id].confirmedTable & index) == 0);
        proposals[id].confirmedTable |= index;
        if (proposals[id].confirmNeeded > 0) {
            proposals[id].confirmNeeded -= 1;
        }
        ProposalConfirmation(id, msg.sender);
    }

    function executeProposal(uint64 id) public {
        require(id >= minApprovedId);
        require(proposals[id].id == id);
        require(proposals[id].confirmNeeded == 0);
        uint256 index = ownerIndex[msg.sender];
        require(index != 0);
        if (giveInfo[id].id == id) {
            require(getRemainingLikeCoins() >= giveInfo[id].value);
            lockedCoin += giveInfo[id].value;
            giveUnlockTime[id] = now + lockDuration;
        } else if (setOwnersInfo[id].id == id) {
            for (uint8 i = 0; i < owners.length; i++) {
                ownerIndex[owners[i]] = 0;
            }
            owners.length = 0;
            for (i = 0; i < setOwnersInfo[id].newOwners.length; i++) {
                owners.push(setOwnersInfo[id].newOwners[i]);
                ownerIndex[setOwnersInfo[id].newOwners[i]] = uint256(1) << i;
            }
            threshold = setOwnersInfo[id].newThreshold;
            minApprovedId = nextId;
            delete setOwnersInfo[id];
			delete proposals[id];
        } else {
            revert();
        }
        ProposalExecution(id, msg.sender);
    }

    function claim(uint64 id) public {
        require(proposals[id].id == id);
        address claimer = msg.sender;
        require(giveInfo[id].to == claimer);
        require(giveUnlockTime[id] > 0);
        require(giveUnlockTime[id] < now);
        uint256 likeCoin = giveInfo[id].value;
        delete proposals[id];
        delete giveInfo[id];
        delete giveUnlockTime[id];
        like.transfer(claimer, likeCoin);
        lockedCoin -= likeCoin;
        Claimed(id);
    }
}
