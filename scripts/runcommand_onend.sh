#!/bin/sh
if ! systemctl is-active --quiet xboxdrv.service; then
    sudo systemctl start xboxdrv.service
fi
