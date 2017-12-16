# Load RUCKUS library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load Source Code
if { $::env(VIVADO_VERSION) >= 2017.3 } {

   loadSource -dir  "$::DIR_PATH/rtl"

   loadSource -path "$::DIR_PATH/coregen/XauiGthUltraScale156p25MHz10GigECore.dcp"
   # loadIpCore -path "$::DIR_PATH/coregen/XauiGthUltraScale156p25MHz10GigECore.xci"

} else {
   puts "\n\nWARNING: $::DIR_PATH requires Vivado 2017.3 (or later)\n\n"
}   