// SPDX-License-Identifier: AGPL-3.0-or-later

// FIXME: Pay shares dependently on the ORIGINAL author

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import './BaseToken.sol';
import './ABDKMath64x64.sol';

abstract contract BaseFiles is BaseToken {

    using ABDKMath64x64 for int128;

    enum EntryKind { NONE, DOWNLOADS, LINK, CATEGORY }

    uint256 constant LINK_KIND_LINK = 0;
    uint256 constant LINK_KIND_MESSAGE = 1;

    string public name;
    uint8 public decimals;
    string public symbol;

    // 64.64 fixed point number
    int128 public salesOwnersShare = int128(1).divi(int128(10)); // 10%
    int128 public upvotesOwnersShare = int128(1).divi(int128(2)); // 50%
    int128 public uploadOwnersShare = int128(15).divi(int128(100)); // 15%
    int128 public buyerAffiliateShare = int128(1).divi(int128(10)); // 10%
    int128 public sellerAffiliateShare = int128(15).divi(int128(100)); // 15%
    int128 public arToETHCoefficient = int128(8).divi(int128(10)); // 80%

    uint maxId = 0;

    mapping (uint => EntryKind) public entries;

    mapping (address => address payable) public accountsMapping;
    mapping (address => address payable) public reverseAccountsMapping;

    // to avoid categories with duplicate titles:
    mapping (string => mapping (string => uint)) public categoryTitles; // locale => (title => id)

    mapping (string => address payable) public nickAddresses;
    mapping (address => string) public addressNicks;

    event SetOwner(address payable owner); // share is 64.64 fixed point number
    event SetSalesOwnerShare(int128 share); // share is 64.64 fixed point number
    event SetUpvotesOwnerShare(int128 share); // share is 64.64 fixed point number
    event SetUploadOwnerShare(int128 share); // share is 64.64 fixed point number
    event SetBuyerAffiliateShare(int128 share); // share is 64.64 fixed point number
    event SetSellerAffiliateShare(int128 share); // share is 64.64 fixed point number
    event SetARToETHCoefficient(int128 coeff); // share is 64.64 fixed point number
    event TransferAuthorship(address payable _orig, address payable _new);
    event SetNick(address payable indexed author, string nick);
    event SetARWallet(address payable indexed authro, string arWallet);
    event SetAuthorInfo(address payable indexed author, string link, string shortDescription, string description, string locale);
    event ItemCreated(uint indexed itemId);
    event SetItemOwner(uint indexed itemId, address payable indexed author);
    event ItemUpdated(uint indexed itemId, ItemInfo info);
    event LinkUpdated(uint indexed linkId,
                      string link,
                      string title,
                      string shortDescription,
                      string description,
                      string locale,
                      uint256 indexed linkKind);
    event ItemCoverUpdated(uint indexed itemId, uint indexed version, bytes cover, uint width, uint height);
    event ItemFilesUpdated(uint indexed itemId, string format, uint indexed version, bytes hash);
    event SetLastItemVersion(uint indexed itemId, uint version);
    event CategoryCreated(uint256 indexed categoryId, address indexed author); // zero author - no owner
    event CategoryUpdated(uint256 indexed categoryId, string title, string locale);
    event OwnedCategoryUpdated(uint256 indexed categoryId,
                               string title, string shortDescription,
                               string description,
                               string locale,
                               address indexed author);
    event ChildParentVote(uint child,
                          uint parent,
                          int256 value,
                          int256 featureLevel,
                          bool primary); // Vote is primary if it's an author's vote. // FIXME: if split ownership?
    event Pay(address indexed payer, address indexed payee, uint indexed itemId, uint256 value);
    event Donate(address indexed payer, address indexed payee, uint indexed itemId, uint256 value);

    address payable public founder;
    mapping (uint => address payable) public itemOwners;
    mapping (uint => mapping (uint => int256)) private childParentVotes;
    mapping (uint => uint256) public pricesETH;
    mapping (uint => uint256) public pricesAR;

    constructor(address payable _founder, uint256 _initialBalance) public {
        founder = _founder;
        name = "Zon Directory PST Token (ETH)";
        decimals = 18;
        symbol = "ZDPSTE";
        balances[_founder] = _initialBalance;
        totalSupply = _initialBalance;
    }

// Owners //

    function setMainOwner(address payable _founder) external {
        require(msg.sender == founder, "Access denied.");
        require(_founder != address(0), "Zero address."); // also prevents makeing owned categories unowned (spam)
        founder = _founder;
        emit SetOwner(_founder);
    }

    function removeMainOwner() external {
        require(msg.sender == founder, "Access denied.");
        founder = address(0);
        emit SetOwner(address(0));
    }

    // _share is 64.64 fixed point number
    function setSalesOwnersShare(int128 _share) external {
        require(msg.sender == founder, "Access denied.");
        salesOwnersShare = _share;
        emit SetSalesOwnerShare(_share);
    }

    function setUpvotesOwnersShare(int128 _share) external {
        require(msg.sender == founder, "Access denied.");
        upvotesOwnersShare = _share;
        emit SetUpvotesOwnerShare(_share);
    }

    function setUploadOwnersShare(int128 _share) external {
        require(msg.sender == founder, "Access denied.");
        uploadOwnersShare = _share;
        emit SetUploadOwnerShare(_share);
    }

    function setBuyerAffiliateShare(int128 _share) external {
        require(msg.sender == founder, "Access denied.");
        buyerAffiliateShare = _share;
        emit SetBuyerAffiliateShare(_share);
    }

    function setSellerAffiliateShare(int128 _share) external {
        require(msg.sender == founder, "Access denied.");
        sellerAffiliateShare = _share;
        emit SetSellerAffiliateShare(_share);
    }

    function setARToETHCoefficient(int128 _coeff) external {
        require(msg.sender == founder, "Access denied.");
        arToETHCoefficient = _coeff;
        emit SetARToETHCoefficient(_coeff);
    }

    function setItemOwner(uint _itemId, address payable _author) external {
        require(_effectiveAccount(itemOwners[_itemId]) == msg.sender, "Access denied.");
        require(_author != address(0), "Zero address.");
        itemOwners[_itemId] = _author;
        emit SetItemOwner(_itemId, _author);
    }

    function removeItemOwner(uint _itemId) external {
        require(_effectiveAccount(itemOwners[_itemId]) == msg.sender, "Access denied.");
        itemOwners[_itemId] = address(0);
        emit SetItemOwner(_itemId, address(0));
    }

// Wallets //

    function setARWallet(string calldata _arWallet) external {
        emit SetARWallet(msg.sender, _arWallet);
    }

    // TODO: Test.
    function setNick(string calldata _nick) external {
        require(nickAddresses[_nick] == address(0), "Nick taken.");
        nickAddresses[addressNicks[msg.sender]] = address(0);
        nickAddresses[_nick] = msg.sender;
        addressNicks[msg.sender] = _nick;
        emit SetNick(msg.sender, _nick);
    }

    function setAuthorInfo(string calldata _link,
                           string calldata _shortDescription,
                           string calldata _description,
                           string calldata _locale) external {
        emit SetAuthorInfo(msg.sender, _link, _shortDescription, _description, _locale);
    }

// Items //

    struct ItemInfo {
        string title;
        string shortDescription;
        string description;
        uint256 priceETH;
        string locale;
        string license;
    }

    function createItem(ItemInfo calldata _info, address payable _affiliate) external returns (uint)
    {
        return _createItem(_info, _affiliate);
    }

    function _createItem(ItemInfo calldata _info, address payable _affiliate) public returns (uint)
    {
        require(bytes(_info.title).length != 0, "Empty title.");
        setAffiliate(_affiliate);
        itemOwners[++maxId] = msg.sender;
        pricesETH[maxId] = _info.priceETH;
        entries[maxId] = EntryKind.DOWNLOADS;
        emit ItemCreated(maxId);
        emit SetItemOwner(maxId, msg.sender);
        emit ItemUpdated(maxId, _info);
        return maxId;
    }

    function updateItem(uint _itemId, ItemInfo calldata _info) external
    {
        require(_effectiveAccount(itemOwners[_itemId]) == msg.sender, "Attempt to modify other's item.");
        require(entries[_itemId] == EntryKind.DOWNLOADS, "Item does not exist.");
        require(bytes(_info.title).length != 0, "Empty title.");
        pricesETH[_itemId] = _info.priceETH;
        emit ItemUpdated(_itemId, _info);
    }

    struct LinkInfo {
        string link;
        string title;
        string shortDescription;
        string description;
        string locale;
        uint256 linkKind;
    }

    function createLink(LinkInfo calldata _info, bool _owned, address payable _affiliate) external returns (uint)
    {
        return _createLink(_info, _owned, _affiliate);
    }

    function _createLink(LinkInfo calldata _info, bool _owned, address payable _affiliate) public returns (uint)
    {
        require(bytes(_info.title).length != 0, "Empty title.");
        setAffiliate(_affiliate);
        address payable _author = _owned ? msg.sender : address(0);
        itemOwners[++maxId] = _author;
        entries[maxId] = EntryKind.LINK;
        emit ItemCreated(maxId);
        if (_owned) emit SetItemOwner(maxId, _author);
        emit LinkUpdated(maxId, _info.link, _info.title, _info.shortDescription, _info.description, _info.locale, _info.linkKind);
        return maxId;
    }

    // Can be used for spam.
    function updateLink(uint _linkId, LinkInfo calldata _info) external
    {
        require(itemOwners[_linkId] == msg.sender, "Attempt to modify other's link."); // only owned links
        require(bytes(_info.title).length != 0, "Empty title.");
        require(entries[_linkId] == EntryKind.LINK, "Link does not exist.");
        emit LinkUpdated(_linkId,
                         _info.link,
                         _info.title,
                         _info.shortDescription,
                         _info.description,
                         _info.locale,
                         _info.linkKind);
    }

    function updateItemCover(uint _itemId, uint _version, bytes calldata _cover, uint _width, uint _height) external {
        require(_effectiveAccount(itemOwners[_itemId]) == msg.sender, "Access denied."); // only owned entries
        EntryKind kind = entries[_itemId];
        require(kind != EntryKind.NONE, "Entry does not exist.");
        emit ItemCoverUpdated(_itemId, _version, _cover, _width, _height);
    }

    function uploadFile(uint _itemId, uint _version, string calldata _format, bytes calldata _hash) external {
        require(_hash.length == 32, "Wrong hash length.");
        require(_effectiveAccount(itemOwners[_itemId]) == msg.sender, "Attempt to modify other's item.");
        require(entries[_itemId] == EntryKind.DOWNLOADS, "Item does not exist.");
        emit ItemFilesUpdated(_itemId, _format, _version, _hash);
    }

    function setLastItemVersion(uint _itemId, uint _version) external {
        require(_effectiveAccount(itemOwners[_itemId]) == msg.sender, "Attempt to modify other's item.");
        require(entries[_itemId] == EntryKind.DOWNLOADS, "Item does not exist.");
        emit SetLastItemVersion(_itemId, _version);
    }

    function pay(uint _itemId, address payable _affiliate) external payable returns (bytes memory) {
        require(pricesETH[_itemId] <= msg.value, "Paid too little.");
        require(entries[_itemId] == EntryKind.DOWNLOADS, "Item does not exist.");
        setAffiliate(_affiliate);
        uint256 _shareholdersShare = uint256(salesOwnersShare.muli(int256(msg.value)));
        address payable _author = itemOwners[_itemId];
        payToShareholders(_shareholdersShare, _author);
        uint256 toAuthor = msg.value - _shareholdersShare;
        _author.transfer(toAuthor);
        emit Pay(msg.sender, itemOwners[_itemId], _itemId, toAuthor);
    }

    function donate(uint _itemId, address payable _affiliate) external payable returns (bytes memory) {
        require(entries[_itemId] == EntryKind.DOWNLOADS, "Item does not exist.");
        setAffiliate(_affiliate);
        uint256 _shareholdersShare = uint256(salesOwnersShare.muli(int256(msg.value)));
        address payable _author = itemOwners[_itemId];
        payToShareholders(_shareholdersShare, _author);
        uint256 toAuthor = msg.value - _shareholdersShare;
        _author.transfer(toAuthor);
        emit Donate(msg.sender, itemOwners[_itemId], _itemId, toAuthor);
    }

// Categories //

    function createCategory(string calldata _title, string calldata _locale, address payable _affiliate) external returns (uint) {
        return _createCategory(_title, _locale, _affiliate);
    }

    function _createCategory(string calldata _title, string calldata _locale, address payable _affiliate) public returns (uint) {
        require(bytes(_title).length != 0, "Empty title.");
        setAffiliate(_affiliate);
        ++maxId;
        uint _id = categoryTitles[_locale][_title];
        if(_id != 0)
            return _id;
        else
            categoryTitles[_locale][_title] = maxId;
        entries[maxId] = EntryKind.CATEGORY;
        // Yes, issue ID two times, for faster information retrieval
        emit CategoryCreated(maxId, address(0));
        emit CategoryUpdated(maxId, _title, _locale);
        return maxId;
    }

    struct OwnedCategoryInfo {
        string title;
        string shortDescription;
        string description;
        string locale;
    }

    function createOwnedCategory(OwnedCategoryInfo calldata _info, address payable _affiliate) external returns (uint) {
        return _createOwnedCategory(_info, _affiliate);
    }

    function _createOwnedCategory(OwnedCategoryInfo calldata _info, address payable _affiliate) public returns (uint) {
        require(bytes(_info.title).length != 0, "Empty title.");
        setAffiliate(_affiliate);
        ++maxId;
        entries[maxId] = EntryKind.CATEGORY;
        itemOwners[maxId] = msg.sender;
        // Yes, issue ID two times, for faster information retrieval
        emit CategoryCreated(maxId, msg.sender);
        emit SetItemOwner(maxId, msg.sender);
        emit OwnedCategoryUpdated(maxId, _info.title, _info.shortDescription, _info.description, _info.locale, msg.sender);
        return maxId;
    }

    function updateOwnedCategory(uint _categoryId, OwnedCategoryInfo calldata _info) external {
        require(itemOwners[_categoryId] == msg.sender, "Access denied.");
        require(entries[_categoryId] == EntryKind.CATEGORY, "Must be a category.");
        emit OwnedCategoryUpdated(_categoryId, _info.title, _info.shortDescription, _info.description, _info.locale, msg.sender);
    }

// Voting //

    function voteChildParent(uint _child, uint _parent, bool _yes, address payable _affiliate) external payable {
        _voteChildParent(_child, _parent, _yes, _affiliate, msg.value);
    }

    function _voteChildParent(uint _child, uint _parent, bool _yes, address payable _affiliate, uint256 _amount) public {
        require(entries[_child] != EntryKind.NONE, "Child does not exist.");
        require(entries[_parent] == EntryKind.CATEGORY, "Must be a category.");
        setAffiliate(_affiliate);
        int256 _value = _yes ? int256(_amount) : -int256(_amount);
        if(_value == 0) return; // We don't want to pollute the events with zero votes.
        int256 _newValue = childParentVotes[_child][_parent] + _value;
        childParentVotes[_child][_parent] = _newValue;
        address payable _author = itemOwners[_child];
        if(_yes && _author != address(0)) {
            uint256 _shareholdersShare = uint256(upvotesOwnersShare.muli(int256(_amount)));
            payToShareholders(_shareholdersShare, _author);
            _author.transfer(_amount - _shareholdersShare);
        } else
            payToShareholders(_amount, address(0));
        emit ChildParentVote(_child, _parent, _newValue, 0, false);
    }

    function voteForOwnChild(uint _child, uint _parent) external payable {
        require(entries[_child] != EntryKind.NONE, "Child does not exist.");
        require(entries[_parent] == EntryKind.CATEGORY, "Must be a category.");
        address _author = itemOwners[_child];
        require(_author == msg.sender, "Must be owner.");
        if(msg.value == 0) return; // We don't want to pollute the events with zero votes.
        int256 _value = upvotesOwnersShare.inv().muli(int256(msg.value));
        int256 _newValue = childParentVotes[_child][_parent] + _value;
        childParentVotes[_child][_parent] = _newValue;
        payToShareholders(msg.value, address(0));
        emit ChildParentVote(_child, _parent, _newValue, 0, false);
    }

    function setMyChildParent(uint _child, uint _parent, int256 _value, int256 _featureLevel) external {
        _setMyChildParent(_child, _parent, _value, _featureLevel);
    }

    // _value > 0 - present
    function _setMyChildParent(uint _child, uint _parent, int256 _value, int256 _featureLevel) public {
        require(entries[_child] != EntryKind.NONE, "Child does not exist.");
        require(entries[_parent] == EntryKind.CATEGORY, "Must be a category.");
        require(itemOwners[_parent] == msg.sender, "Access denied.");
        emit ChildParentVote(_child, _parent, _value, _featureLevel, true);
    }

    function getChildParentVotes(uint _child, uint _parent) external view returns (int256) {
        return childParentVotes[_child][_parent];
    }

// PST //

    uint256 totalDividends = 0;
    uint256 totalDividendsPaid = 0; // actually paid sum
    mapping(address => uint256) lastTotalDivedends; // the value of totalDividends after the last payment to an address

    function _dividendsOwing(address _account) internal view returns(uint256) {
        uint256 _newDividends = totalDividends - lastTotalDivedends[_account];
        return (balances[_account] * _newDividends) / totalSupply; // rounding down
    }

    function dividendsOwing(address _account) external view returns(uint256) {
        return _dividendsOwing(_account);
    }

    function withdrawProfit() external {
        uint256 _owing = _dividendsOwing(msg.sender);

        // Against rounding errors. Not necessary because of rounding down.
        // if(_owing > address(this).balance) _owing = address(this).balance;

        if(_owing > 0) {
            msg.sender.transfer(_owing);
            totalDividendsPaid += _owing;
            lastTotalDivedends[msg.sender] = totalDividends;
        }
    }

    function payToShareholders(uint256 _amount, address _author) internal {
        address payable _buyerAffiliate = affiliates[msg.sender];
        address payable _sellerAffiliate = affiliates[_author];
        uint256 _shareHoldersAmount = _amount;
        if(uint(_buyerAffiliate) > 1) {
            uint256 _buyerAffiliateAmount = uint256(buyerAffiliateShare.muli(int256(_amount)));
            _buyerAffiliate.transfer(_buyerAffiliateAmount);
            require(_shareHoldersAmount >= _buyerAffiliateAmount, "Attempt to pay negative amount.");
            _shareHoldersAmount -= _buyerAffiliateAmount;
        }
        if(uint(_sellerAffiliate) > 1) {
            uint256 _sellerAffiliateAmount = uint256(sellerAffiliateShare.muli(int256(_amount)));
            payable(_sellerAffiliate).transfer(_sellerAffiliateAmount);
            require(_shareHoldersAmount >= _sellerAffiliateAmount, "Attempt to pay negative amount.");
            _shareHoldersAmount -= _sellerAffiliateAmount;
        }
        totalDividends += _shareHoldersAmount;
    }

// Affiliates //

    mapping (address => address payable) affiliates;

    // Last affiliate wins.
    function setAffiliate(address payable _affiliate) internal {
        // if(affiliates[_affiliate] == address(0))
        //     affiliates[_affiliate] = _affiliate;
        if(uint256(_affiliate) > 1)
            affiliates[msg.sender] = _affiliate;
    }

// Authorship //

    function transferAuthorship(address payable _newAuthor) external {
        require(_newAuthor != address(0), "Zero address.");
        address payable _orig = _originalAccount(_newAuthor);
        accountsMapping[_orig] = _newAuthor;
        reverseAccountsMapping[_newAuthor] = _orig;
        emit TransferAuthorship(_orig, _newAuthor);
    }

    function _effectiveAccount(address payable _orig) internal view returns (address payable) {
        address payable _result = accountsMapping[_orig];
        return _result != address(0) ? _result : _orig;
    }

    function _originalAccount(address payable _effective) internal view returns (address payable) {
        address payable _result = reverseAccountsMapping[_effective];
        return _result != address(0) ? _result : _effective;
    }
}
