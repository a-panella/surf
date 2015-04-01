-------------------------------------------------------------------------------
-- Title      : 
-------------------------------------------------------------------------------
-- File       : TenGigEthGtx7Wrapper.vhd
-- Author     : Larry Ruckman <ruckman@slac.stanford.edu>
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2015-03-30
-- Last update: 2015-03-30
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: Gtx7 Wrapper for 10GBASE-R Ethernet
-- Note: This module supports up to a MGT QUAD of 10GigE interfaces
-------------------------------------------------------------------------------
-- Copyright (c) 2015 SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

use work.StdRtlPkg.all;
use work.AxiStreamPkg.all;
use work.AxiLitePkg.all;
use work.TenGigEthPkg.all;
use work.TenGigEthGtx7Pkg.all;

entity TenGigEthGtx7Wrapper is
   -- Defaults:
   -- 9 bits = 4kbytes
   -- 255 x 8 = 2kbytes (not enough for pause)
   -- 11 bits = 16kbytes 
   generic (
      TPD_G              : time                             := 1 ns;
      -- DMA/MAC Configurations
      IB_ADDR_WIDTH_G    : NaturalArray(3 downto 0)         := (others => 11);
      OB_ADDR_WIDTH_G    : NaturalArray(3 downto 0)         := (others => 9);
      PAUSE_THOLD_G      : NaturalArray(3 downto 0)         := (others => 512);
      VALID_THOLD_G      : NaturalArray(3 downto 0)         := (others => 255);
      EOH_BIT_G          : NaturalArray(3 downto 0)         := (others => 0);
      ERR_BIT_G          : NaturalArray(3 downto 0)         := (others => 1);
      HEADER_SIZE_G      : NaturalArray(3 downto 0)         := (others => 16);
      SHIFT_EN_G         : BooleanArray(3 downto 0)         := (others => false);
      MAC_ADDR_G         : Slv48Array(3 downto 0)           := (others => TEN_GIG_ETH_MAC_ADDR_INIT_C);
      NUM_LANE_G         : natural range 1 to 4             := 1;
      -- QUAD PLL Configurations
      REFCLK_DIV2_G      : boolean                          := false;  --  FALSE: gtClkP/N = 156.25 MHz,  TRUE: gtClkP/N = 312.5 MHz
      QPLL_REFCLK_SEL_G  : bit_vector                       := "001";
      -- AXI-Lite Configurations
      AXI_ERROR_RESP_G   : slv(1 downto 0)                  := AXI_RESP_SLVERR_C;
      STATUS_CNT_WIDTH_G : natural range 1 to 32            := 32;
      -- AXI Streaming Configurations
      -- Note: Only support 64-bit AXIS configurations on the XMAC module
      AXIS_CONFIG_G      : AxiStreamConfigArray(3 downto 0) := (others => AXI_STREAM_CONFIG_INIT_C));
   port (
      -- Streaming DMA Interface 
      dmaClk              : in  slv(NUM_LANE_G-1 downto 0);
      dmaRst              : in  slv(NUM_LANE_G-1 downto 0);
      dmaIbMasters        : out AxiStreamMasterArray(NUM_LANE_G-1 downto 0);
      dmaIbSlaves         : in  AxiStreamSlaveArray(NUM_LANE_G-1 downto 0);
      dmaObMasters        : in  AxiStreamMasterArray(NUM_LANE_G-1 downto 0);
      dmaObSlaves         : out AxiStreamSlaveArray(NUM_LANE_G-1 downto 0);
      -- Slave AXI-Lite Interface 
      axiLiteClk          : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '0');
      axiLiteRst          : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '0');
      axiLiteReadMasters  : in  AxiLiteReadMasterArray(NUM_LANE_G-1 downto 0)  := (others => AXI_LITE_READ_MASTER_INIT_C);
      axiLiteReadSlaves   : out AxiLiteReadSlaveArray(NUM_LANE_G-1 downto 0);
      axiLiteWriteMasters : in  AxiLiteWriteMasterArray(NUM_LANE_G-1 downto 0) := (others => AXI_LITE_WRITE_MASTER_INIT_C);
      axiLiteWriteSlaves  : out AxiLiteWriteSlaveArray(NUM_LANE_G-1 downto 0);
      -- SFP+ Ports
      sigDet              : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '1');
      txFault             : in  slv(NUM_LANE_G-1 downto 0)                     := (others => '0');
      txDisable           : out slv(NUM_LANE_G-1 downto 0);
      -- Misc. Signals
      extRst              : in  sl;
      phyClk              : out sl;
      phyRst              : out sl;
      phyReady            : out slv(NUM_LANE_G-1 downto 0);
      -- MGT Clock Port (156.25 MHz or 312.5 MHz)
      gtClkP              : in  sl;
      gtClkN              : in  sl;
      -- MGT Ports
      gtTxP               : out slv(NUM_LANE_G-1 downto 0);
      gtTxN               : out slv(NUM_LANE_G-1 downto 0);
      gtRxP               : in  slv(NUM_LANE_G-1 downto 0);
      gtRxN               : in  slv(NUM_LANE_G-1 downto 0));  
end TenGigEthGtx7Wrapper;

architecture mapping of TenGigEthGtx7Wrapper is

   signal phyClock : sl;
   signal phyReset : sl;

   signal qplllock      : sl;
   signal qplloutclk    : sl;
   signal qplloutrefclk : sl;

   signal qpllRst   : slv(NUM_LANE_G-1 downto 0);
   signal qpllReset : sl;

begin

   phyClk <= phyClock;
   phyRst <= phyReset;

   ----------------------
   -- Common Clock Module 
   ----------------------
   TenGigEthGtx7Clk_Inst : entity work.TenGigEthGtx7Clk
      generic map (
         TPD_G             => TPD_G,
         REFCLK_DIV2_G     => REFCLK_DIV2_G,
         QPLL_REFCLK_SEL_G => QPLL_REFCLK_SEL_G)         
      port map (
         -- Clocks and Resets
         extRst        => extRst,
         phyClk        => phyClock,
         phyRst        => phyReset,
         -- MGT Clock Port (156.25 MHz or 312.5 MHz)
         gtClkP        => gtClkP,
         gtClkN        => gtClkN,
         -- Quad PLL Ports
         qplllock      => qplllock,
         qplloutclk    => qplloutclk,
         qplloutrefclk => qplloutrefclk,
         qpllRst       => qpllReset);        

   qpllReset <= uOr(qpllRst) and not(qPllLock);

   ----------------
   -- 10GigE Module 
   ----------------
   GEN_LANE :
   for i in 0 to NUM_LANE_G-1 generate
      
      TenGigEthGtx7_Inst : entity work.TenGigEthGtx7
         generic map (
            TPD_G              => TPD_G,
            -- DMA/MAC Configurations
            IB_ADDR_WIDTH_G    => IB_ADDR_WIDTH_G(i),
            OB_ADDR_WIDTH_G    => OB_ADDR_WIDTH_G(i),
            PAUSE_THOLD_G      => PAUSE_THOLD_G(i),
            VALID_THOLD_G      => VALID_THOLD_G(i),
            EOH_BIT_G          => EOH_BIT_G(i),
            ERR_BIT_G          => ERR_BIT_G(i),
            HEADER_SIZE_G      => HEADER_SIZE_G(i),
            SHIFT_EN_G         => SHIFT_EN_G(i),
            MAC_ADDR_G         => MAC_ADDR_G(i),
            -- AXI-Lite Configurations
            AXI_ERROR_RESP_G   => AXI_ERROR_RESP_G,
            STATUS_CNT_WIDTH_G => STATUS_CNT_WIDTH_G,
            -- AXI Streaming Configurations
            AXIS_CONFIG_G      => AXIS_CONFIG_G(i))       
         port map (
            -- Streaming DMA Interface 
            dmaClk             => dmaClk(i),
            dmaRst             => dmaRst(i),
            dmaIbMaster        => dmaIbMasters(i),
            dmaIbSlave         => dmaIbSlaves(i),
            dmaObMaster        => dmaObMasters(i),
            dmaObSlave         => dmaObSlaves(i),
            -- Slave AXI-Lite Interface 
            axiLiteClk         => axiLiteClk(i),
            axiLiteRst         => axiLiteRst(i),
            axiLiteReadMaster  => axiLiteReadMasters(i),
            axiLiteReadSlave   => axiLiteReadSlaves(i),
            axiLiteWriteMaster => axiLiteWriteMasters(i),
            axiLiteWriteSlave  => axiLiteWriteSlaves(i),
            -- SFP+ Ports
            sigDet             => sigDet(i),
            txFault            => txFault(i),
            txDisable          => txDisable(i),
            -- Misc. Signals
            extRst             => extRst,
            phyClk             => phyClock,
            phyRst             => phyReset,
            phyReady           => phyReady(i),
            -- Quad PLL Ports
            qplllock           => qplllock,
            qplloutclk         => qplloutclk,
            qplloutrefclk      => qplloutrefclk,
            -- MGT Ports
            gtTxP              => gtTxP(i),
            gtTxN              => gtTxN(i),
            gtRxP              => gtRxP(i),
            gtRxN              => gtRxN(i));  

   end generate GEN_LANE;

end mapping;