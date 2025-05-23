// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IL2OpEURCDeploy {
  /*///////////////////////////////////////////////////////////////
                            STRUCTS
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice The struct to hold the EURC data for the name, symbol, currency, and decimals when initializing
   * @param tokenName The name of the EURC token
   * @param tokenSymbol The symbol of the EURC token
   * @param tokenCurrency The currency that the EURC token represents
   * @param tokenDecimals The number of decimals that the EURC token uses
   */
  struct EURCInitializeData {
    string tokenName;
    string tokenSymbol;
    string tokenCurrency;
    uint8 tokenDecimals;
  }

  /*///////////////////////////////////////////////////////////////
                            EVENTS
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted when the EURC implementation is deployed
   * @param _l2EurcImplementation The address of the L2 EURC implementation
   */
  event EURCImplementationDeployed(address _l2EurcImplementation);

  /**
   * @notice Emitted when the EURC proxy is deployed
   * @param _l2EurcProxy The address of the L2 EURC proxy
   */
  event EURCProxyDeployed(address _l2EurcProxy);

  /**
   * @notice Emitted when the L2 adapter is deployed
   * @param _l2Adapter The address of the L2 adapter
   */
  event L2AdapterDeployed(address _l2Adapter);

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  ///////////////////////////////////////////////////////////////*/

  /**
   * @notice Thrown when a contract deployment fails
   */
  error IL2OpEURCDeploy_DeploymentFailed();

  /**
   * @notice Thrown when an EURC initialization tx failed
   * @param _txIndex The index of the failed initialization tx
   */
  error IL2OpEURCDeploy_InitializationFailed(uint256 _txIndex);
}
