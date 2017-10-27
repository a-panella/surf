-------------------------------------------------------------------------------
-- File       : Pgp3GthUsWrapper.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-27
-- Last update: 2017-10-27
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'SLAC Firmware Standard Library'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC Firmware Standard Library', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.AxiLitePkg.all;
use work.Pgp3Pkg.all;

library unisim;
use unisim.vcomponents.all;

entity Pgp3GthUsWrapper is
   generic (
      TPD_G                           : time                   := 1 ns;
      NUM_LANE_G                      : positive range 1 to 4  := 1;
      NUM_VC_G                        : positive range 1 to 16 := 4;
      REFCLK_G                        : boolean                := false;  --  FALSE: pgpRefClkP/N,  TRUE: pgpRefClkIn
      ----------------------------------------------------------------------------------------------
      -- PGP Settings
      ----------------------------------------------------------------------------------------------
      PGP_RX_ENABLE_G                 : boolean                := true;
      RX_ALIGN_GOOD_COUNT_G           : integer                := 128;
      RX_ALIGN_BAD_COUNT_G            : integer                := 16;
      RX_ALIGN_SLIP_WAIT_G            : integer                := 32;
      PGP_TX_ENABLE_G                 : boolean                := true;
      TX_CELL_WORDS_MAX_G             : integer                := 256;  -- Number of 64-bit words per cell
      TX_SKP_INTERVAL_G               : integer                := 5000;
      TX_SKP_BURST_SIZE_G             : integer                := 8;
      TX_MUX_MODE_G                   : string                 := "INDEXED";  -- Or "ROUTED"
      TX_MUX_TDEST_ROUTES_G           : Slv8Array              := (0 => "--------");  -- Only used in ROUTED mode
      TX_MUX_TDEST_LOW_G              : integer range 0 to 7   := 0;
      TX_MUX_INTERLEAVE_EN_G          : boolean                := true;
      TX_MUX_INTERLEAVE_ON_NOTVALID_G : boolean                := true;
      AXIL_CLK_FREQ_G                 : real                   := 125.0E+6;
      AXI_ERROR_RESP_G                : slv(1 downto 0)        := AXI_RESP_DECERR_C);
   port (
      -- Stable Clock and Reset
      stableClk        : in  sl;        -- GT needs a stable clock to "boot up"
      stableRst        : in  sl;
      -- Gt Serial IO
      pgpGtTxP         : out slv(NUM_LANE_G-1 downto 0);
      pgpGtTxN         : out slv(NUM_LANE_G-1 downto 0);
      pgpGtRxP         : in  slv(NUM_LANE_G-1 downto 0);
      pgpGtRxN         : in  slv(NUM_LANE_G-1 downto 0);
      -- GT Clocking
      pgpRefClkP       : in  sl                                             := '0';
      pgpRefClkN       : in  sl                                             := '1';
      pgpRefClkIn      : in  sl                                             := '0';
      pgpRefClkOut     : out sl;
      -- Clocking
      pgpClk           : out slv(NUM_LANE_G-1 downto 0);
      pgpClkRst        : out slv(NUM_LANE_G-1 downto 0);
      -- Non VC Rx Signals
      pgpRxIn          : in  Pgp3RxInArray(NUM_LANE_G-1 downto 0);
      pgpRxOut         : out Pgp3RxOutArray(NUM_LANE_G-1 downto 0);
      -- Non VC Tx Signals
      pgpTxIn          : in  Pgp3TxInArray(NUM_LANE_G-1 downto 0);
      pgpTxOut         : out Pgp3TxOutArray(NUM_LANE_G-1 downto 0);
      -- Frame Transmit Interface
      pgpTxMasters     : in  AxiStreamMasterArray((NUM_LANE_G*NUM_VC_G)-1 downto 0);
      pgpTxSlaves      : out AxiStreamSlaveArray((NUM_LANE_G*NUM_VC_G)-1 downto 0);
      -- Frame Receive Interface
      pgpRxMasters     : out AxiStreamMasterArray((NUM_LANE_G*NUM_VC_G)-1 downto 0);
      pgpRxCtrl        : in  AxiStreamCtrlArray((NUM_LANE_G*NUM_VC_G)-1 downto 0);
      -- AXI-Lite Register Interface (axilClk domain)
      axilClk          : in  sl                                             := '0';  -- Stable Clock
      axilRst          : in  sl                                             := '0';
      axilReadMasters  : in  AxiLiteReadMasterArray(NUM_LANE_G-1 downto 0)  := (others => AXI_LITE_READ_MASTER_INIT_C);
      axilReadSlaves   : out AxiLiteReadSlaveArray(NUM_LANE_G-1 downto 0)   := (others => AXI_LITE_READ_SLAVE_INIT_C);
      axilWriteMasters : in  AxiLiteWriteMasterArray(NUM_LANE_G-1 downto 0) := (others => AXI_LITE_WRITE_MASTER_INIT_C);
      axilWriteSlaves  : out AxiLiteWriteSlaveArray(NUM_LANE_G-1 downto 0)  := (others => AXI_LITE_WRITE_SLAVE_INIT_C));
end Pgp3GthUsWrapper;

architecture rtl of Pgp3GthUsWrapper is

   signal qpllLock   : Slv2Array(3 downto 0) := (others => "00");
   signal qpllclk    : Slv2Array(3 downto 0) := (others => "00");
   signal qpllrefclk : Slv2Array(3 downto 0) := (others => "00");
   signal qpllRst    : Slv2Array(3 downto 0) := (others => "00");

   signal pgpRefClock : sl;
   signal pgpRefClk   : sl;

begin

   pgpRefClkOut <= pgpRefClk;

   U_pgpRefClk : IBUFDS_GTE3
      generic map (
         REFCLK_EN_TX_PATH  => '0',
         REFCLK_HROW_CK_SEL => "00",    -- 2'b00: ODIV2 = O
         REFCLK_ICNTL_RX    => "00")
      port map (
         I     => pgpRefClkP,
         IB    => pgpRefClkN,
         CEB   => '0',
         ODIV2 => open,
         O     => pgpRefClock);

   pgpRefClk <= pgpRefClock when(REFCLK_G = false) else pgpRefClkIn;

   U_QPLL : entity work.Pgp3GthUsQpll
      generic map (
         TPD_G            => TPD_G,
         AXI_ERROR_RESP_G => AXI_ERROR_RESP_G)
      port map (
         -- Stable Clock and Reset
         stableClk  => stableClk,
         stableRst  => stableRst,
         -- QPLL Clocking
         pgpRefClk  => pgpRefClk,
         qpllLock   => qpllLock,
         qpllclk    => qpllclk,
         qpllrefclk => qpllrefclk,
         qpllRst    => qpllRst);

   -----------
   -- PGP Core
   -----------
   GEN_LANE :
   for i in NUM_LANE_G-1 downto 0 generate

      U_Pgp : entity work.Pgp3GthUs
         generic map (
            TPD_G                           => TPD_G,
            ----------------------------------------------------------------------------------------------
            -- PGP Settings
            ----------------------------------------------------------------------------------------------
            PGP_RX_ENABLE_G                 => PGP_RX_ENABLE_G,
            RX_ALIGN_GOOD_COUNT_G           => RX_ALIGN_GOOD_COUNT_G,
            RX_ALIGN_BAD_COUNT_G            => RX_ALIGN_BAD_COUNT_G,
            RX_ALIGN_SLIP_WAIT_G            => RX_ALIGN_SLIP_WAIT_G,
            PGP_TX_ENABLE_G                 => PGP_TX_ENABLE_G,
            NUM_VC_G                        => NUM_VC_G,
            TX_CELL_WORDS_MAX_G             => TX_CELL_WORDS_MAX_G,
            TX_SKP_INTERVAL_G               => TX_SKP_INTERVAL_G,
            TX_SKP_BURST_SIZE_G             => TX_SKP_BURST_SIZE_G,
            TX_MUX_MODE_G                   => TX_MUX_MODE_G,
            TX_MUX_TDEST_ROUTES_G           => TX_MUX_TDEST_ROUTES_G,
            TX_MUX_TDEST_LOW_G              => TX_MUX_TDEST_LOW_G,
            TX_MUX_INTERLEAVE_EN_G          => TX_MUX_INTERLEAVE_EN_G,
            TX_MUX_INTERLEAVE_ON_NOTVALID_G => TX_MUX_INTERLEAVE_ON_NOTVALID_G,
            AXIL_CLK_FREQ_G                 => AXIL_CLK_FREQ_G,
            AXI_ERROR_RESP_G                => AXI_ERROR_RESP_G)
         port map (
            -- Stable Clock and Reset
            stableClk       => stableClk,
            stableRst       => stableRst,
            -- QPLL Interface
            qpllLock        => qpllLock(i),
            qpllclk         => qpllclk(i),
            qpllrefclk      => qpllrefclk(i),
            qpllRst         => qpllRst(i),
            -- Gt Serial IO
            pgpGtTxP        => pgpGtTxP(i),
            pgpGtTxN        => pgpGtTxN(i),
            pgpGtRxP        => pgpGtRxP(i),
            pgpGtRxN        => pgpGtRxN(i),
            -- Clocking
            pgpClk          => pgpClk(i),
            pgpClkRst       => pgpClkRst(i),
            -- Non VC Rx Signals
            pgpRxIn         => pgpRxIn(i),
            pgpRxOut        => pgpRxOut(i),
            -- Non VC Tx Signals
            pgpTxIn         => pgpTxIn(i),
            pgpTxOut        => pgpTxOut(i),
            -- Frame Transmit Interface
            pgpTxMasters    => pgpTxMasters(((i+1)*NUM_VC_G)-1 downto (i*NUM_VC_G)),
            pgpTxSlaves     => pgpTxSlaves(((i+1)*NUM_VC_G)-1 downto (i*NUM_VC_G)),
            -- Frame Receive Interface
            pgpRxMasters    => pgpRxMasters(((i+1)*NUM_VC_G)-1 downto (i*NUM_VC_G)),
            pgpRxCtrl       => pgpRxCtrl(((i+1)*NUM_VC_G)-1 downto (i*NUM_VC_G)),
            -- AXI-Lite Register Interface (axilClk domain)
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(i),
            axilReadSlave   => axilReadSlaves(i),
            axilWriteMaster => axilWriteMasters(i),
            axilWriteSlave  => axilWriteSlaves(i));

   end generate GEN_LANE;

end rtl;
