-------------------------------------------------------------------------------
-- File       : UartRx.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2016-05-13
-- Last update: 2018-05-03
-------------------------------------------------------------------------------
-- Description: UART Receiver
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
use ieee.std_logic_unsigned.all;

use work.StdRtlPkg.all;

entity UartRx is
  generic (
    TPD_G        : time                 := 1 ns;
    PARITY_EN_G  : integer range 0 to 1 := 0;  -- 0 is 0 parity bit, 1 stop bit | 1 is 0/1 parity bit, 2/1 stop bit
    PARITY_G     : string               := "NONE";  -- "NONE" "ODD" "EVEN"
    DATA_WIDTH_G : integer range 5 to 8 := 8);
  port (
    clk         : in  sl;
    rst         : in  sl;
    baud16x     : in  sl;
    rdData      : out slv(7 downto 0);
    rdValid     : out sl;
    parityError : out sl;
    rdReady     : in  sl;
    rx          : in  sl);
end entity UartRx;

architecture rtl of UartRx is

  type StateType is (WAIT_START_BIT_S, WAIT_8_S, WAIT_16_S, SAMPLE_RX_S, PARITY_S, WAIT_STOP_S, WRITE_OUT_S);

  type RegType is
  record
    rdValid      : sl;
    rdData       : slv(DATA_WIDTH_G-1 downto 0);
    rxState      : stateType;
    rxShiftReg   : slv(DATA_WIDTH_G-1 downto 0);
    rxShiftCount : slv(3 downto 0);
    baud16xCount : slv(3 downto 0);
    parity       : sl;
    parityError  : sl;
  end record regType;

  constant REG_INIT_C : RegType := (
    rdValid      => '0',
    rdData       => (others => '0'),
    rxState      => WAIT_START_BIT_S,
    rxShiftReg   => (others => '0'),
    rxShiftCount => (others => '0'),
    baud16xCount => (others => '0'),
    parity       => '0',
    parityError  => '0');

  signal r   : RegType := REG_INIT_C;
  signal rin : RegType;

  signal rxSync : sl;
  signal rxFall : sl;


begin

  U_SynchronizerEdge_1 : entity work.SynchronizerEdge
    generic map (
      TPD_G    => TPD_G,
      STAGES_G => 3,
      INIT_G   => "111")
    port map (
      clk         => clk,               -- [in]
      rst         => rst,               -- [in]
      dataIn      => rx,                -- [in]
      dataOut     => rxSync,            -- [out]
      risingEdge  => open,              -- [out]
      fallingEdge => rxFall);           -- [out]

  comb : process (baud16x, r, rdReady, rst, rxFall, rxSync) is
    variable v : RegType;
  begin
    v := r;

    if (rdReady = '1') then
      v.rdValid := '0';
    end if;

    case r.rxState is

      -- Wait for RX to drop to indicate start bit
      when WAIT_START_BIT_S =>
        if (rxFall = '1') then
          v.rxState      := WAIT_8_S;
          v.baud16xCount := "0000";
          v.rxShiftCount := "0000";
        end if;

        -- Wait 8 baud16x counts to find center of start bit
        -- Every rx bit is 16 baud16x pulses apart
        -- reset parity error flag
      when WAIT_8_S =>
        v.parityError := '0';
        if (baud16x = '1') then
          v.baud16xCount := r.baud16xCount + 1;
          if (r.baud16xCount = "0111") then
            v.baud16xCount := "0000";
            v.rxState      := WAIT_16_S;
          end if;
        end if;

        -- Wait 16 baud16x counts (center of next bit)
      when WAIT_16_S =>
        if (baud16x = '1') then
          v.baud16xCount := r.baud16xCount + 1;
          if (r.baud16xCount = "1111") then
            if (r.rxShiftCount = DATA_WIDTH_G and PARITY_EN_G = 1) then
              v.rxState := PARITY_S;
              v.parity  := oddParity(v.rxShiftReg);
            else
              v.rxState := SAMPLE_RX_S;
            end if;
          end if;
        end if;

        -- Sample the rx line and shift it in.
        -- Go back and wait 16 for the next bit unless last bit
      when SAMPLE_RX_S =>
        v.rxShiftReg   := rxSync & r.rxShiftReg(DATA_WIDTH_G-1 downto 1);
        v.rxShiftCount := r.rxShiftCount + 1;
        v.rxState      := WAIT_16_S;
        if (r.rxShiftCount = DATA_WIDTH_G-1) then
          if(PARITY_EN_G = 1) then
            v.rxState := WAIT_16_S;
          else
            v.rxState := WAIT_STOP_S;
          end if;
        end if;

        -- Samples parity bit on rx line and compare it to the calculated parity
        -- raises a parityError flag if it does not match
      when PARITY_S =>
        case PARITY_G is
          when "NONE" => v.rxState := WAIT_STOP_S;
          when "EVEN" =>
            if(v.parity = rxSync) then
              v.rxState := WAIT_STOP_S;
            else
              v.parityError := '1';
            end if;
          when "ODD" =>
            if(not(v.parity) = rxSync) then
              v.rxState := WAIT_STOP_S;
            else
              v.parityError := '1';
            end if;
          when others => null;
        end case;

        -- Wait for the stop bit
      when WAIT_STOP_S =>
        if (rxSync = '1') then
          v.rxState := WRITE_OUT_S;
        end if;

        -- Put the parallel rx data on the output port.
      when WRITE_OUT_S =>
        v.rdData  := r.rxShiftReg;
        v.rdValid := '1';
        v.rxState := WAIT_START_BIT_S;

    end case;

    if (rst = '1') then
      v := REG_INIT_C;
    end if;

    rin         <= v;
    rdData      <= r.rdData;
    rdValid     <= r.rdValid;
    parityError <= r.parityError;
    
  end process comb;

  sync : process (clk) is
  begin
    if (rising_edge(clk)) then
      r <= rin after TPD_G;
    end if;
  end process;

end architecture RTL;
