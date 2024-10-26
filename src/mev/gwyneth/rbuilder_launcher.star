static_files = import_module("../../static_files/static_files.star")
shared_utils = import_module("../../shared_utils/shared_utils.star")

# let datadir_base = "/data/reth/gwyneth";
# let ipc_base: &str = "/tmp/reth.ipc";

L1_DATA_MOUNT = "/data/reth/execution-data"
L2_DATA_MOUNT = "/data/reth/gwyneth"
IPC_MOUNT = "/tmp/reth.ipc"
RBUILDER_CONFIG_NAME = "config-gwyneth-reth.toml"

RBUILDER_RPC_PORT = 9646


USED_PORTS = {
    "http": shared_utils.new_port_spec(
        RBUILDER_RPC_PORT, shared_utils.TCP_PROTOCOL
    )
}

def launch(
    plan,
    beacon_uri,
    el_l2_networks,
    el_context,
    mev_params,
    global_node_selectors,
):
    el_rpc_uri = "http://{0}:{1}".format(el_context.ip_addr, el_context.rpc_port_num)

    l2_data_paths = []
    l2_ipc_paths = []
    files = {
        # /data/reth/execution-data/: data-el-1-gwyneth-lighthouse
        L1_DATA_MOUNT: Directory(persistent_key="data-{0}".format(el_context.service_name))
    }
    for i, network in enumerate(el_l2_networks):
        # /data/reth/gwyneth-160010: data-el-1-gwyneth-lighthouse-160010
        mount_path = "{0}-{1}".format(L2_DATA_MOUNT, network)
        l2_data_paths.append(mount_path)
        files[l2_data_paths[i]] = Directory(persistent_key="data-{0}-{1}".format(el_context.service_name, network))
        # /tmp/reth.ipc-160010: data-el-1-gwyneth-lighthouse-160010
        mount_path = "{0}-{1}".format(IPC_MOUNT, network)
        l2_ipc_paths.append(mount_path)
        files[l2_ipc_paths[i]] = el_context.ipc_files[i]

    config_template_file = read_file(static_files.L2_RBUILDER_CONFIG_FILEPATH)
    template_data = new_rbuilder_template_data(
        beacon_uri,
        el_rpc_uri,
        l2_data_paths,
        l2_ipc_paths,
        mev_params
    )
    template_and_data = shared_utils.new_template_and_data(config_template_file, template_data)
    template_and_data_filepath = {}
    template_and_data_filepath[RBUILDER_CONFIG_NAME] = template_and_data
    config_artifact = plan.render_templates(
        template_and_data_filepath, "rbuilder-config-toml"
    )
    # /config/config-gwyneth-reth.toml: rbuilder-config-gwyneth-reth
    files["/config"] = config_artifact
    plan.print("Rbuilder config {0}".format(template_data))

    service_config = ServiceConfig(
        image=mev_params.mev_builder_image,
        ports=USED_PORTS,
        files=files,
        entrypoint=["/app/rbuilder"],
        cmd=[
            "run",
            "/config/" + RBUILDER_CONFIG_NAME
        ]
    )
    service_name = "rbuilder-{0}".format(el_context.service_name)
    
    plan.add_service(service_name, service_config)


def new_rbuilder_template_data(
    beacon_uri,
    el_rpc_uri,
    l2_data_paths,
    l2_ipc_paths,
    mev_params
):
    return {
        "BeaconUri": beacon_uri,
        "RbuilderRpcPort": RBUILDER_RPC_PORT,
        "RethRpcUri": el_rpc_uri,
        "L1DataPath": L1_DATA_MOUNT,
        "L2DataPaths": l2_data_paths,
        "L2IpcPaths": l2_ipc_paths,
        "L1ProposerPk": mev_params.l1_proposer_pk,
        "L1GwynethAddress": mev_params.l1_gwyneth_address,
    }