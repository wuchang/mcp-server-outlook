#!/bin/bash
cd /data/workcode/notebooks/microsoft/mcp-server-outlook/src
for f in log.zig main.zig token_cache.zig; do
    sed -i 's|@cInclude("stdlib.h")|@cDefine("__STDC_LIB_EXT1__","0")\n    @cInclude("stdlib.h")|g; s|@cInclude("stdio.h")|@cDefine("__STDC_LIB_EXT1__","0")\n    @cInclude("stdio.h")|g' "$f"
done
echo "done"