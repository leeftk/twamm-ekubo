use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DisplayClassHash, DisplayContractAddress,
    DeployResult, InvokeResult, CallResult, get_nonce, FeeSettings, EthFeeSettings
};
use starknet::ClassHash;
fn main() {
    let max_fee = 999999999999999;
    let salt = 0x3;

    // let declare_nonce = get_nonce('latest');

    let class_hash: ClassHash = 0x210dca9ade7fec696a1128f9fb05be95bd5b4114f42031e010f2c2ec09adf0b.try_into().unwrap();
    let deploy_nonce = get_nonce('pending');

    let deploy_result = deploy(
        class_hash,
        array![
            0x48ce784a8c6522f9964bd38871813203529f3c834d6350c39b63d569f353169
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
