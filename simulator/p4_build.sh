#!/bin/bash

PROGRAM=$1
if [ -z $1 ]; then
    echo "PROGRAM is missing";
    echo "Usage: ./p4_build.sh PROGRAM";
    exit 1
fi

# Check parameters
if [ -z ${SDE+x} ]; then
    echo "SDE is unset";
    echo "set: $SDE=~/bf-sde-x.y.z/";
    exit 1
else
    echo "SDE is set to '$SDE'";
fi

if [ -z ${SDE_INSTALL+x} ]; then
    echo "SDE_INSTALL is unset";
    echo "set: $SDE_INSTALL=$SDE/install'";
    exit 1
else
    echo "SDE_INSTALL is set to '$SDE_INSTALL'";
fi

ARCH=tofino

cd $SDE_INSTALL/bin

# Compile P4 code into binaries
./p4c $PROJECT_SRC/src/$PROGRAM/$PROGRAM.p4 -b $ARCH -o $SDE_INSTALL/share/p4/targets/$ARCH/$PROGRAM --std p4-16 --Wdisable

# Generate conf files to simulator
./p4c-gen-bfrt-conf --name $PROGRAM --device $ARCH --pipe pipe --testdir $SDE_INSTALL/share/p4/targets/$ARCH/$PROGRAM --installdir $SDE_INSTALL/share/p4/targets/$ARCH/$PROGRAM
mv $SDE_INSTALL/share/p4/targets/$ARCH/$PROGRAM/bfrt.json $SDE_INSTALL/share/p4/targets/$ARCH/$PROGRAM/bf-rt.json

if [ $? == 0 ]; then
    echo "Compilou com sucesso."
else
    echo "Falha ao compilar."
fi