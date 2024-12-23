use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DisplayClassHash, DeployResult, InvokeResult,
    CallResult, get_nonce, FeeSettings, EthFeeSettings
};
use starknet::ClassHash;

fn main() {
    let max_fee = 999999999999999;
    let salt = 0x3;

    // let declare_nonce = get_nonce('latest');

    let class_hash: ClassHash = 0x052a64ba6b5fb5b12dd5b7ea80c649bab2e695e36d547886001229bd69a340a6.try_into().unwrap();

    let deploy_nonce = get_nonce('pending');

    let deploy_result = deploy(
        class_hash,
        ArrayTrait::new(),
        Option::Some(salt),
        true,
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(deploy_nonce)
    )
        .expect('TokenBridgeHelper deploy failed');

    assert(deploy_result.transaction_hash != 0, deploy_result.transaction_hash);

    println!("TokenBridgeHelper deploy result: ", deploy_result);
}
