{ lib
,
}:

{ nebulaRuntimePlan ? {
    overlays = { };
    nodes = { };
  }
, externalLighthouseReturnIpv4Cidrs ? [ ]
, externalLighthousePublicIpv4SecretPath ? null
, externalLighthousePublicIpv6SecretPath ? null
, externalLighthouseSshHostSecretPath ? externalLighthousePublicIpv4SecretPath
, externalPortForwardPublicIpv4SecretPath ? externalLighthousePublicIpv4SecretPath
, externalPortForwardPublicIpv6SecretPath ? externalLighthousePublicIpv6SecretPath
, externalPortForwardNodeNames ? [ ]
, externalRuntimeNodeNames ? externalPortForwardNodeNames
, runtimeListenHosts ? { }
, externalRemoteLighthouseEndpoint4 ? null
, externalRemoteLighthouseEndpoint6 ? null
, externalRemoteLighthouseEndpoint4SecretPath ? null
, externalRemoteLighthouseEndpoint6SecretPath ? null
, externalSuppressPublicLighthouseStaticMap ? false
, sopsProfileSecretPrefix ? null
,
}:
import ./spec.nix {
  inherit
    lib
    nebulaRuntimePlan
    externalLighthouseReturnIpv4Cidrs
    externalLighthousePublicIpv4SecretPath
    externalLighthousePublicIpv6SecretPath
    externalLighthouseSshHostSecretPath
    externalPortForwardPublicIpv4SecretPath
    externalPortForwardPublicIpv6SecretPath
    externalPortForwardNodeNames
    externalRuntimeNodeNames
    runtimeListenHosts
    externalRemoteLighthouseEndpoint4
    externalRemoteLighthouseEndpoint6
    externalRemoteLighthouseEndpoint4SecretPath
    externalRemoteLighthouseEndpoint6SecretPath
    externalSuppressPublicLighthouseStaticMap
    sopsProfileSecretPrefix
    ;
}
