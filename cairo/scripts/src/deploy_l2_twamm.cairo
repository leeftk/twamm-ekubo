use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DisplayClassHash, DisplayContractAddress,  DeployResult, InvokeResult,
    CallResult, get_nonce, FeeSettings, EthFeeSettings
};

fn main() {
    let max_fee = 999999999999999;
    let salt = 0x3;

    let declare_nonce = get_nonce('latest');

    let declare_result = declare(
        "L2TWAMMBridge",
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(declare_nonce)
    )
        .expect('map declare failed');

    let class_hash = declare_result.class_hash;
    let deploy_nonce = get_nonce('pending');

    let deploy_result = deploy(
        class_hash,
        array![0x6741d6978d88014ed5230ff58f38d2ded28554ca15160d7fe59fb83d6cb43c8], // owner's address
        Option::Some(salt),
        true,
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(deploy_nonce)
    )
        .expect('L2TWAMM deploy failed');

    assert(deploy_result.transaction_hash != 0, deploy_result.transaction_hash);

    let invoke_nonce = get_nonce('pending');

    let invoke_result = invoke(
        deploy_result.contract_address,
        selector!("put"),
        array![0x1, 0x2],
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(invoke_nonce)
    )
        .expect('map invoke failed');

    assert(invoke_result.transaction_hash != 0, invoke_result.transaction_hash);

    let call_result = call(deploy_result.contract_address, selector!("get"), array![0x1])
        .expect('map call failed');

    assert(call_result.data == array![0x2], *call_result.data.at(0));
}