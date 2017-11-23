pragma solidity 0.4.18;

/// @title Test token contract - Allows testing of token transfers with multisig wallet.
contract TestToken {

    /*
     *  Events
     */
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /*
     *  Constants
     */
    string constant public name = "Test Token";
    string constant public symbol = "TT";
    uint8 constant public decimals = 1;

    /*
     *  Storage
     */
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
    uint256 public totalSupply;

    /*
     * Public functions
     */
    /// @dev Issues new tokens.
    /// @param _to Address of token receiver.
    /// @param _value Number of tokens to issue.
    function issueTokens(address _to, uint256 _value)
        public
    {
        balances[_to] += _value;
        totalSupply += _value;
    }

    /// @dev Transfers sender's tokens to a given address. Returns success.
    /// @param _to Address of token receiver.
    /// @param _value Number of tokens to transfer.
    /// @return Returns success of function call.
    function transfer(address _to, uint256 _value)
        public
        returns (bool success)
    {
        if (balances[msg.sender] < _value) {
            throw;
        }
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        Transfer(msg.sender, _to, _value);
        return true;
    }

    /// @dev Allows allowed third party to transfer tokens from one address to another. Returns success.
    /// @param _from Address from where tokens are withdrawn.
    /// @param _to Address to where tokens are sent.
    /// @param _value Number of tokens to transfer.
    /// @return Returns success of function call.
    function transferFrom(address _from, address _to, uint256 _value)
        public
        returns (bool success)
    {
        if (balances[_from] < _value || allowed[_from][msg.sender] < _value) {
            throw;
        }
        balances[_to] += _value;
        balances[_from] -= _value;
        allowed[_from][msg.sender] -= _value;
        Transfer(_from, _to, _value);
        return true;
    }

    /// @dev Sets approved amount of tokens for spender. Returns success.
    /// @param _spender Address of allowed account.
    /// @param _value Number of approved tokens.
    /// @return Returns success of function call.
    function approve(address _spender, uint256 _value)
        public
        returns (bool success)
    {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    /// @dev Returns number of allowed tokens for given address.
    /// @param _owner Address of token owner.
    /// @param _spender Address of token spender.
    /// @return Returns remaining allowance for spender.
    function allowance(address _owner, address _spender)
        constant
        public
        returns (uint256 remaining)
    {
        return allowed[_owner][_spender];
    }

    /// @dev Returns number of tokens owned by given address.
    /// @param _owner Address of token owner.
    /// @return Returns balance of owner.
    function balanceOf(address _owner)
        constant
        public
        returns (uint256 balance)
    {
        return balances[_owner];
    }
}



/// @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.
/// @author Stefan George - <stefan.george@consensys.net>
contract MultiSigWallet {

    /*
     *  Events
     */
    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Submission(uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event Deposit(address indexed sender, uint value);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event RequirementChange(uint required);

    /*
     *  Constants
     */
    uint constant public MAX_OWNER_COUNT = 50;

    /*
     *  Storage
     */
    mapping (uint => Transaction) public transactions;
    mapping (uint => Transfer) public transfers;
    mapping (uint => mapping (address => bool)) public transactionConfirmations;
    mapping (uint => mapping (address => bool)) public transferConfirmations;
    mapping (address => bool) public isOwner;
    address[] public owners;
    uint public required;
    uint public transactionCount;
    uint public transferCount;
    address tokenContract;

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        bool executed;
    }

    struct Transfer {
        address destination;
        uint value;
        bool executed;
    }

    /*
     *  Modifiers
     */
    modifier onlyWallet() {
        if (msg.sender != address(this))
            throw;
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        if (isOwner[owner])
            throw;
        _;
    }

    modifier ownerExists(address owner) {
        if (!isOwner[owner])
            throw;
        _;
    }

    modifier actionExists(uint actionId, bool transfer) {
        if (transfer) {
            require(transfers[actionId].destination != 0);
        }
        else {
            require(transactions[actionId].destination != 0);
        }
        _;
    }

    modifier confirmed(uint actionId, address owner, bool transfer) {
        if (transfer) {
            require(transferConfirmations[actionId][owner]);
        }
        else {
            require(transactionConfirmations[actionId][owner]);
        }
        _;
    }

    modifier notConfirmed(uint actionId, address owner, bool transfer) {
        if (transfer) {
            require(!transferConfirmations[actionId][owner]);
        }
        else {
            require(!transactionConfirmations[actionId][owner]);
        }
        _;
    }

    modifier notExecuted(uint actionId, bool transfer) {
        if (transfer) {
            require(!transfers[actionId].executed);
        }
        else {
            require(!transactions[actionId].executed);
        }
        _;
    }

    modifier notNull(address _address) {
        if (_address == 0)
            throw;
        _;
    }

    modifier validRequirement(uint ownerCount, uint _required) {
        if (   ownerCount > MAX_OWNER_COUNT
            || _required > ownerCount
            || _required == 0
            || ownerCount == 0)
            throw;
        _;
    }

    /// @dev Fallback function allows to deposit ether.
    function()
        payable
    {
        if (msg.value > 0)
            Deposit(msg.sender, msg.value);
    }

    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    function MultiSigWallet(address _tokenContract, address[] _owners, uint _required)
        public
        validRequirement(_owners.length, _required)
    {
        for (uint i=0; i<_owners.length; i++) {
            if (isOwner[_owners[i]] || _owners[i] == 0)
                throw;
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
        tokenContract = _tokenContract;
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of new owner.
    function addOwner(address owner)
        public
        onlyWallet
        ownerDoesNotExist(owner)
        notNull(owner)
        validRequirement(owners.length + 1, required)
    {
        isOwner[owner] = true;
        owners.push(owner);
        OwnerAddition(owner);
    }

    /// @dev Allows to remove an owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner.
    function removeOwner(address owner)
        public
        onlyWallet
        ownerExists(owner)
    {
        isOwner[owner] = false;
        for (uint i=0; i<owners.length - 1; i++)
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        owners.length -= 1;
        if (required > owners.length)
            changeRequirement(owners.length);
        OwnerRemoval(owner);
    }

    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner to be replaced.
    /// @param newOwner Address of new owner.
    function replaceOwner(address owner, address newOwner)
        public
        onlyWallet
        ownerExists(owner)
        ownerDoesNotExist(newOwner)
    {
        for (uint i=0; i<owners.length; i++)
            if (owners[i] == owner) {
                owners[i] = newOwner;
                break;
            }
        isOwner[owner] = false;
        isOwner[newOwner] = true;
        OwnerRemoval(owner);
        OwnerAddition(newOwner);
    }

    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(uint _required)
        public
        onlyWallet
        validRequirement(owners.length, _required)
    {
        required = _required;
        RequirementChange(_required);
    }


    /// @dev Allows an owner to submit and confirm a transfer.
    /// @param destination Transfer target address.
    /// @param value Transfer value.
    /// @return Returns transfer ID.
    function submitTransfer(address destination, uint value)
        public
        returns (uint transferId)
    {
        transferId = addTransfer(destination, value);
        confirmTransfer(transferId);
    }


    /// @dev Allows an owner to confirm a transfer.
    /// @param transferId Transfer ID.
    function confirmTransfer(uint transferId)
        public
        ownerExists(msg.sender)
        actionExists(transferId, true)
        notConfirmed(transferId, msg.sender, true)
    {
        transferConfirmations[transferId][msg.sender] = true;
        Confirmation(msg.sender, transferId);
        executeTransfer(transferId);
    }


    /// @dev Allows anyone to execute a confirmed transfer.
    /// @param transferId Transfer ID.
    function executeTransfer(uint transferId)
        public
        ownerExists(msg.sender)
        confirmed(transferId, msg.sender, true)
        notExecuted(transferId, true)
    {
        if (isConfirmedTransfer(transferId)) {
            Transfer transfer = transfers[transferId];
            transfer.executed = true;
            TestToken token = TestToken(tokenContract);
            if (token.transfer(transfer.destination, transfer.value))
                Execution(transferId);
            else {
                ExecutionFailure(transferId);
                transfer.executed = false;
            }
        }
    }

    /// @dev Returns the confirmation status of a transfer.
    /// @param transferId Transfer ID.
    /// @return Confirmation status.
    function isConfirmedTransfer(uint transferId)
        public
        constant
        returns (bool)
    {
        uint count = 0;
        for (uint i=0; i<owners.length; i++) {
            if (transferConfirmations[transferId][owners[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transfer to the transfer mapping, if transfer does not exist yet.
    /// @param destination Transfer target address.
    /// @param value Transfer value.
    /// @return Returns transfer ID.
    function addTransfer(address destination, uint value)
        internal
        notNull(destination)
        returns (uint transferId)
    {
        transferId = transferCount;
        transfers[transferId] = Transfer({
            destination: destination,
            value: value,
            executed: false
        });
        transferCount += 1;
        Submission(transferId);
    }




    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function submitTransaction(address destination, uint value, bytes data)
        public
        returns (uint transactionId)
    {
        transactionId = addTransaction(destination, value, data);
        confirmTransaction(transactionId);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint transactionId)
        public
        ownerExists(msg.sender)
        actionExists(transactionId, false)
        notConfirmed(transactionId, msg.sender, false)
    {
        transactionConfirmations[transactionId][msg.sender] = true;
        Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId);
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param transactionId Transaction ID.
    function revokeConfirmation(uint transactionId)
        public
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender, false)
        notExecuted(transactionId, false)
    {
        transactionConfirmations[transactionId][msg.sender] = false;
        Revocation(msg.sender, transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint transactionId)
        public
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender, false)
        notExecuted(transactionId, false)
    {
        if (isConfirmedTransaction(transactionId)) {
            Transaction tx = transactions[transactionId];
            tx.executed = true;
            if (tx.destination.call.value(tx.value)(tx.data))
                Execution(transactionId);
            else {
                ExecutionFailure(transactionId);
                tx.executed = false;
            }
        }
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Confirmation status.
    function isConfirmedTransaction(uint transactionId)
        public
        constant
        returns (bool)
    {
        uint count = 0;
        for (uint i=0; i<owners.length; i++) {
            if (transactionConfirmations[transactionId][owners[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function addTransaction(address destination, uint value, bytes data)
        internal
        notNull(destination)
        returns (uint transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        });
        transactionCount += 1;
        Submission(transactionId);
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns number of confirmations of an action.
    /// @param actionId Action ID.
    /// @return Number of confirmations.
    function getConfirmationCount(uint actionId, bool transfer)
        public
        constant
        returns (uint count)
    {
        uint i=0;
        if (transfer) {
            for (;i<owners.length; i++)
                if (transferConfirmations[actionId][owners[i]])
                    count += 1;
        } else {
            for (;i<owners.length; i++)
                if (transactionConfirmations[actionId][owners[i]])
                    count += 1;        
        }
    }

    /// @dev Returns total number of actions after filers are applied.
    /// @param pending Include pending actions.
    /// @param executed Include executed actions.
    /// @return Total number of actions after filters are applied.
    function getActionCount(bool pending, bool executed, bool transfer)
        public
        constant
        returns (uint count)
    {
        uint i=0;
        if (transfer) {
            for (; i<transferCount; i++)
                if (   pending && !transfers[i].executed
                    || executed && transfers[i].executed)
                    count += 1;            
        }
        else {
            for (; i<transactionCount; i++)
                if (   pending && !transactions[i].executed
                    || executed && transactions[i].executed)
                    count += 1;
        }
    }


    /// @dev Returns list of owners.
    /// @return List of owner addresses.
    function getOwners()
        public
        constant
        returns (address[])
    {
        return owners;
    }

    /// @dev Returns token contract address.
    /// @return token contract address.
    function getTokenContract()
        public
        constant
        returns (address)
    {
        return tokenContract;
    }


    /// @dev Returns array with owner addresses, which confirmed transfer.
    /// @param transferId Transfer ID.
    /// @return Returns array of owner addresses.
    function getTransferConfirmations(uint transferId)
        public
        constant
        returns (address[] _confirmations)
    {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint count = 0;
        uint i;
        for (i=0; i<owners.length; i++)
            if (transferConfirmations[transferId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i=0; i<count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    /// @dev Returns array with owner addresses, which confirmed transaction.
    /// @param transactionId Transaction ID.
    /// @return Returns array of owner addresses.
    function getTransactionConfirmations(uint transactionId)
        public
        constant
        returns (address[] _confirmations)
    {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint count = 0;
        uint i;
        for (i=0; i<owners.length; i++)
            if (transactionConfirmations[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i=0; i<count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param from Index start position of transaction array.
    /// @param to Index end position of transaction array.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(uint from, uint to, bool pending, bool executed)
        public
        constant
        returns (uint[] _transactionIds)
    {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
            {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        _transactionIds = new uint[](to - from);
        for (i=from; i<to; i++)
            _transactionIds[i - from] = transactionIdsTemp[i];
    }


    /// @dev Returns list of transfer IDs in defined range.
    /// @param from Index start position of transfer array.
    /// @param to Index end position of transfer array.
    /// @param pending Include pending transfer.
    /// @param executed Include executed transfer.
    /// @return Returns array of transfer IDs.
    function getTransferIds(uint from, uint to, bool pending, bool executed)
        public
        constant
        returns (uint[] _transferIds)
    {
        uint[] memory transferIdsTemp = new uint[](transferCount);
        uint count = 0;
        uint i;
        for (i=0; i<transferCount; i++)
            if (   pending && !transfers[i].executed
                || executed && transfers[i].executed)
            {
                transferIdsTemp[count] = i;
                count += 1;
            }
        _transferIds = new uint[](to - from);
        for (i=from; i<to; i++)
            _transferIds[i - from] = transferIdsTemp[i];
    }


}
