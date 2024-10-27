static_files = import_module("../../static_files/static_files.star")
shared_utils = import_module("../../shared_utils/shared_utils.star")

# let datadir_base = "/data/reth/gwyneth";
# let ipc_base: &str = "/tmp/reth.ipc";

L1_DATA_MOUNT = "/data/reth/execution-data"
L2_DATA_MOUNT = "/data/reth/gwyneth"
IPC_MOUNT = "/tmp/ipc"

RBUILDER_CONFIG_NAME = "config-gwyneth-reth.toml"

L1_RPC_PORT = 9646
L2_RPC_PORT = 9647

def launch(
    plan,
    beacon_uri,
    el_l2_networks,
    el_context,
    mev_params,
    global_node_selectors,
):
    el_rpc_uri = "http://{0}:{1}".format(el_context.ip_addr, el_context.rpc_port_num)


    used_ports = {}
    l2_data_paths = []
    l2_ipc_files = []
    files = {
        # /data/reth/execution-data/: data-el-1-gwyneth-lighthouse
        L1_DATA_MOUNT: Directory(persistent_key="data-{0}".format(el_context.service_name)),
        IPC_MOUNT: Directory(persistent_key="ipc-{0}".format(el_context.service_name))
    }
    for i, network in enumerate(el_l2_networks):
        data_mount_path = "{0}-{1}".format(L2_DATA_MOUNT, network)
        l2_data_paths.append(data_mount_path)
        files[data_mount_path] = Directory(persistent_key="data-{0}-{1}".format(el_context.service_name, network))
        l2_ipc_files.append("{0}/l2.ipc-{1}".format(IPC_MOUNT, network))
        used_ports["rbuilder-rpc-l2-{0}".format(network)] = L2_RPC_PORT + i
    
    config_template_file = read_file(static_files.L2_RBUILDER_CONFIG_FILEPATH)
    template_data = new_rbuilder_template_data(
        beacon_uri,
        el_rpc_uri,
        el_l2_networks,
        l2_data_paths,
        l2_ipc_files,
        list(used_ports.values()),
        mev_params
    )
    plan.print("Rbuilder config {0}".format(template_data))
    template_and_data = shared_utils.new_template_and_data(config_template_file, template_data)
    template_and_data_filepath = {}
    template_and_data_filepath[RBUILDER_CONFIG_NAME] = template_and_data
    config_artifact = plan.render_templates(
        template_and_data_filepath, "rbuilder-config-toml"
    )
    files["/config"] = config_artifact
    plan.print("Rbuilder config {0}".format(template_data))

    # Add L1_RPC_PORT to used ports after randering the template
    used_ports["rbuilder-rpc-l1"] = L1_RPC_PORT
    
    service_config = ServiceConfig(
        image=mev_params.mev_builder_image,
        ports=shared_utils.get_port_specs(used_ports),
        files=files,
        cmd=[
            "run",
            "/config/{0}".format(RBUILDER_CONFIG_NAME)
        ]
    )
    service_name = "rbuilder-{0}".format(el_context.service_name)
    
    plan.add_service(service_name, service_config)


def new_rbuilder_template_data(
    beacon_uri,
    el_rpc_uri,
    l2_networks,
    l2_data_paths,
    l2_ipc_files,
    used_ports,
    mev_params
):
    return {
        "BeaconUri": beacon_uri,
        "L1RpcPort": L1_RPC_PORT,
        "RethRpcUri": el_rpc_uri,
        "L1DataPath": L1_DATA_MOUNT,
        "L1IpcPath": IPC_MOUNT + "/l1.ipc",
        "L2ChainIds": l2_networks,
        "L2DataPaths": l2_data_paths,
        "L2IpcPaths": l2_ipc_files,
        "L2RpcPorts": used_ports,
        "L1ProposerPk": mev_params.l1_proposer_pk,
        "L1GwynethAddress": mev_params.l1_gwyneth_address,
    }