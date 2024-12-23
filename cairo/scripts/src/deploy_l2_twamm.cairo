use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DisplayClassHash, DisplayContractAddress,
    DeployResult, InvokeResult, CallResult, get_nonce, FeeSettings, EthFeeSettings
};
use starknet::ClassHash;
fn main() {
    let max_fee = 999999999999999;
    let salt = 0x3;

    // let declare_nonce = get_nonce('latest');

    let class_hash: ClassHash = 0x06ea4671dd9d249530b5fb2b106fa1e287378ea5539d999c98b5959e7db6a3c5.try_into().unwrap();
    let deploy_nonce = get_nonce('pending');

    let deploy_result = deploy(
        class_hash,
        array![
            0x6741d6978d88014ed5230ff58f38d2ded28554ca15160d7fe59fb83d6cb43c8
        ], // owner's address
        Option::Some(salt),
        true,
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(deploy_nonce)
    )
        .expect('L2TWAMM deploy failed');

    assert(deploy_result.transaction_hash != 0, deploy_result.transaction_hash);
    println!("L2TWAMM deploy result: {:?}", deploy_result);

   
}
