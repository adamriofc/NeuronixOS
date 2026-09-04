{ config, lib, pkgs, ... }:

{
  options.neuronix.system.manual = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Embed the complete NEURONIX OS Technical Manual into the system derivation.";
    };
  };

  config = lib.mkIf config.neuronix.system.manual.enable {
    # Declaratively symlink manual into /etc/neuronix/manual
    environment.etc = {
      "neuronix/manual/00_INDEX.md".source = ../../docs/manual/00_INDEX.md;
      "neuronix/manual/01_ARCHITECTURE.md".source = ../../docs/manual/01_ARCHITECTURE.md;
      "neuronix/manual/02_CONFIGURATION_REFERENCE.md".source = ../../docs/manual/02_CONFIGURATION_REFERENCE.md;
      "neuronix/manual/03_CLI_REFERENCE.md".source = ../../docs/manual/03_CLI_REFERENCE.md;
      "neuronix/manual/04_STORAGE_AND_ROLLBACK.md".source = ../../docs/manual/04_STORAGE_AND_ROLLBACK.md;
      "neuronix/manual/05_SHADOW_VM_AND_SANDBOX.md".source = ../../docs/manual/05_SHADOW_VM_AND_SANDBOX.md;
      "neuronix/manual/06_DEVELOPER_STACKS.md".source = ../../docs/manual/06_DEVELOPER_STACKS.md;
      "neuronix/manual/07_MCP_PROTOCOL_AND_AI_GATEWAY.md".source = ../../docs/manual/07_MCP_PROTOCOL_AND_AI_GATEWAY.md;
      "neuronix/manual/08_HARDWARE_AND_27_PILLARS.md".source = ../../docs/manual/08_HARDWARE_AND_27_PILLARS.md;
      "neuronix/manual/09_SECURITY_AND_ATTESTATION.md".source = ../../docs/manual/09_SECURITY_AND_ATTESTATION.md;
      "neuronix/manual/10_AI_AGENT_REFERENCE.md".source = ../../docs/manual/10_AI_AGENT_REFERENCE.md;

      # Standard root directives automatically discovered by AI agents (OpenCode, Cursor, Claude, Antigravity)
      "neuronix/SYSTEM_PROMPT.md".source = ../../docs/manual/10_AI_AGENT_REFERENCE.md;
      "neuronix/AGENTS.md".source = ../../docs/manual/10_AI_AGENT_REFERENCE.md;
    };

    # Ambient environment variables informing all shells and AI agents of manual locations
    environment.variables = {
      NEURONIX_MANUAL_DIR = "/etc/neuronix/manual";
      NEURONIX_SYSTEM_PROMPT = "/etc/neuronix/SYSTEM_PROMPT.md";
      NEURONIX_AI_DIRECTIVE = "/etc/neuronix/manual/10_AI_AGENT_REFERENCE.md";
    };
  };
}
