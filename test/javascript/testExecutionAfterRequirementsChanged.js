const MultiSigWallet = artifacts.require('MultiSigWallet')
const TestToken = artifacts.require('TestToken')

const web3 = MultiSigWallet.web3
const deployMultisig = (tokenAddress, owners, confirmations) => {
    return MultiSigWallet.new(tokenAddress, owners, confirmations)
}

const deployToken = () => {
    return TestToken.new()
}

const utils = require('./utils')
const ONE_DAY = 24*3600
const deposit = 1000
const transfer = 100

contract('MultiSigWallet', (accounts) => {
    let multisigInstance, tokenInstance, multisigInstance2
    const requiredConfirmations = 2

    beforeEach(async () => {
        tokenInstance = await deployToken()
        assert.ok(tokenInstance)
        multisigInstance = await deployMultisig(tokenInstance.address, [accounts[0], accounts[1], accounts[2]], requiredConfirmations)
        assert.ok(multisigInstance)
        assert.equal(await multisigInstance.getTokenContract(), tokenInstance.address)

        multisigInstance2 = await deployMultisig(tokenInstance.address, [accounts[4], accounts[5], accounts[6]], requiredConfirmations)
        assert.ok(multisigInstance2)
        assert.equal(await multisigInstance2.getTokenContract(), tokenInstance.address)


        // Fund multisig 1 with tokens
        const sendTokensData = tokenInstance.contract.issueTokens.getData(multisigInstance.address, deposit)
        fundingTx = await tokenInstance.issueTokens(multisigInstance.address, deposit)
        assert.equal(await tokenInstance.balanceOf(multisigInstance.address), deposit)
    })

    it('test execution after requirements changed', async () => {        
        // Add owner wa_4
        const addOwnerData = multisigInstance.contract.addOwner.getData(accounts[3])
        const transactionId = utils.getParamFromTxEvent(
            await multisigInstance.submitTransaction(multisigInstance.address, 0, addOwnerData, {from: accounts[0]}),
            'transactionId',
            null,
            'Submission'
        )

        // There is one pending transaction
        const excludePending = false
        const includePending = true
        const excludeExecuted = false
        const includeExecuted = true
        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 1, includePending, excludeExecuted),
            [transactionId]
        )

        // Update required to 1
        const newRequired = 1
        const updateRequirementData = multisigInstance.contract.changeRequirement.getData(newRequired)

        // Submit successfully
        const transactionId2 = utils.getParamFromTxEvent(
            await multisigInstance.submitTransaction(multisigInstance.address, 0, updateRequirementData, {from: accounts[0]}),
            'transactionId',
            null,
            'Submission'
        )

        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 2, includePending, excludeExecuted),
            [transactionId, transactionId2]
        )

        // Confirm change requirement transaction
        await multisigInstance.confirmTransaction(transactionId2, {from: accounts[1]})
        assert.equal((await multisigInstance.required()).toNumber(), newRequired)
        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 1, excludePending, includeExecuted),
            [transactionId2]
        )

        // Execution fails, because sender is not wallet owner
        utils.assertThrowsAsynchronously(
            () => multisigInstance.executeTransaction(transactionId, {from: accounts[9]})
        )

        // Because the # required confirmations changed to 1, the addOwner transaction can be executed now
        await multisigInstance.executeTransaction(transactionId, {from: accounts[0]})
        assert.deepEqual(
            await multisigInstance.getTransactionIds(0, 2, excludePending, includeExecuted),
            [transactionId, transactionId2]
        )
    })

    it('test execution token transfer', async () => {
        const transferId = utils.getParamFromTxEvent(
            await multisigInstance.submitTransfer(multisigInstance2.address, transfer, {from: accounts[0]}),
            // Fix this
            'transactionId',
            null,
            'Submission'
        )


        // There is 1 pending transfer
        const excludePending = false
        const includePending = true
        const excludeExecuted = false
        const includeExecuted = true
        assert.deepEqual(
            await multisigInstance.getTransferIds(0, 1, includePending, excludeExecuted),
            [transferId]
        )

        await multisigInstance.confirmTransfer(transferId, {from: accounts[1]})
        assert.equal(await tokenInstance.balanceOf(multisigInstance.address), deposit-transfer)
        assert.equal(await tokenInstance.balanceOf(multisigInstance2.address), transfer)


    })


})