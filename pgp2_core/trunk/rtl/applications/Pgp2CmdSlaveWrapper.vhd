-------------------------------------------------------------------------------
-- Title         : Pretty Good Protocol, V2, Command Slave Block
-- Project       : General Purpose Core
-------------------------------------------------------------------------------
-- File          : Pgp2CmdSlaveWrapper.vhd
-- Author        : Larry Ruckman, ruckman@slac.stanford.edu
-- Created       : 06/11/2013
-------------------------------------------------------------------------------
-- Description:
-- Wrapper for Pgp2CmdSlave
-------------------------------------------------------------------------------
-- Copyright (c) 2013 by Larry Ruckman. All rights reserved.
-------------------------------------------------------------------------------
-- Modification history:
-- 06/11/2013: created.
-------------------------------------------------------------------------------

library ieee;
use work.Pgp2CoreTypesPkg.all;
use work.Pgp2AppTypesPkg.all;
use work.StdRtlPkg.all;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity Pgp2CmdSlaveWrapper is
   generic (
      RxLane   : integer := 0;          -- Receive Lanes Number (0 to 3) 
      DestId   : natural := 0;          -- Destination ID Value To Match
      DestMask : natural := 0;          -- Destination ID Mask For Match
      -- FifoType: (default = V5)
      -- V4 = Virtex 4,  V5 = Virtex 5, V6 = Virtex 6, V7 = Virtex 7, 
      -- S6 = Spartan 6, A7 = Artix 7,  K7 = kintex7
      FifoType : string  := "V5"
      );
   port (

      -- PGP Rx Clock And Reset
      pgpRxClk   : in sl;               -- PGP Clock
      pgpRxReset : in sl;               -- Synchronous PGP Reset

      -- Local clock and reset
      locClk   : in sl;                 -- Local Clock
      locReset : in sl;                 -- Synchronous Local Reset

      -- PGP Signals, Virtual Channel Rx Only
      PgpRxVcOut             : in  PgpRxVcOutType;
      PgpRxVcCommonOut       : in  PgpRxVcCommonOutType;
      pgpTxVcIn_locBuffAFull : out sl;
      pgpTxVcIn_locBuffFull  : out sl;

      -- Local command signals
      CmdSlaveOut : out CmdSlaveOutType
      );

end Pgp2CmdSlaveWrapper;

-- Define architecture
architecture mapping of Pgp2CmdSlaveWrapper is

begin
   U_PgpCmd : entity work.Pgp2CmdSlave
      generic map (
         DestId   => DestId,
         DestMask => DestMask,
         FifoType => FifoType
         ) port map ( 
            pgpRxClk       => pgpRxClk,
            pgpRxReset     => pgpRxReset,
            locClk         => locClk,
            locReset       => locReset,
            vcFrameRxValid => pgpRxVcOut.frameRxValid,
            vcFrameRxSOF   => PgpRxVcCommonOut.frameRxSOF,
            vcFrameRxEOF   => PgpRxVcCommonOut.frameRxEOF,
            vcFrameRxEOFE  => PgpRxVcCommonOut.frameRxEOFE,
            vcFrameRxData  => PgpRxVcCommonOut.frameRxData(RxLane),
            vcLocBuffAFull => pgpTxVcIn_locBuffAFull,
            vcLocBuffFull  => pgpTxVcIn_locBuffFull,
            cmdEn          => CmdSlaveOut.cmdEn,
            cmdOpCode      => CmdSlaveOut.cmdOpCode,
            cmdCtxOut      => CmdSlaveOut.cmdCtxOut
            );
end mapping;