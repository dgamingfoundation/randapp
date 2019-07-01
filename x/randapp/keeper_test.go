package randapp_test

import (
	"fmt"
	"io/ioutil"
	"os"
	"testing"

	"github.com/magiconair/properties/assert"

	"github.com/cosmos/cosmos-sdk/codec"
	"github.com/cosmos/cosmos-sdk/store"
	sdk "github.com/cosmos/cosmos-sdk/types"

	app "github.com/dgamingfoundation/randapp"
	"github.com/dgamingfoundation/randapp/x/randapp"
	"github.com/stretchr/testify/require"

	abci "github.com/tendermint/tendermint/abci/types"
	dbm "github.com/tendermint/tendermint/libs/db"
	"github.com/tendermint/tendermint/libs/log"
	"github.com/tendermint/tendermint/types"
)

var DefaultNodeHome = os.ExpandEnv("$HOME/.kp")

type keeperMockApp struct {
	cdc      *codec.Codec
	nsKeeper randapp.Keeper

	keyPubKeys            *sdk.KVStoreKey
	keyDeals              *sdk.KVStoreKey
	keyResponses          *sdk.KVStoreKey
	keyJustifications     *sdk.KVStoreKey
	keyCommits            *sdk.KVStoreKey
	keyComplaints         *sdk.KVStoreKey
	keyReconstructCommits *sdk.KVStoreKey
}

const keeperMockAppName = "keeperMockApp"

func TestM(t *testing.T) {

	dir, _ := ioutil.TempDir("", "goleveldb-app-sim")
	db, _ := sdk.NewLevelDB("Simulation", dir)
	defer func() {
		db.Close()
		os.RemoveAll(dir)
	}()

	logger := log.NewNopLogger()
	dapp := NewKeeperMockApp(logger, db)
	ms := store.NewCommitMultiStore(db)
	ms.MountStoreWithDB(dapp.keyPubKeys, sdk.StoreTypeIAVL, db)
	ms.MountStoreWithDB(dapp.keyDeals, sdk.StoreTypeIAVL, db)
	ms.MountStoreWithDB(dapp.keyResponses, sdk.StoreTypeIAVL, db)
	ms.MountStoreWithDB(dapp.keyJustifications, sdk.StoreTypeIAVL, db)
	ms.MountStoreWithDB(dapp.keyCommits, sdk.StoreTypeIAVL, db)
	ms.MountStoreWithDB(dapp.keyComplaints, sdk.StoreTypeIAVL, db)
	ms.MountStoreWithDB(dapp.keyReconstructCommits, sdk.StoreTypeIAVL, db)

	err := ms.LoadLatestVersion()
	require.Nil(t, err)

	ctx := sdk.NewContext(ms, abci.Header{}, false, log.NewNopLogger())

	addr := sdk.AccAddress([]byte("mockadress1"))
	dkgData := randapp.DKGData{
		Owner: addr,
		Data: &types.DKGData{
			Type:        types.DKGPubKey,
			RoundID:     -1,
			ToIndex:     0,
			NumEntities: 0,
			Addr:        addr.Bytes(),
		},
	}

	for key := types.DKGPubKey; key <= types.DKGReconstructCommit; key++ {
		dkgData.Data.Type = key
		dkgData.Data.RoundID++
		dkgData.Data.ToIndex++
		dkgData.Data.NumEntities++

		dapp.nsKeeper.AddDKGData(ctx, dkgData)
		d2 := dapp.nsKeeper.GetDKGData(ctx, key)
		assert.Equal(t, fmt.Sprintf("%+v", dkgData.Data), fmt.Sprintf("%+v", d2[0]))
	}
}

func NewKeeperMockApp(logger log.Logger, db dbm.DB) *keeperMockApp {
	cdc := app.MakeCodec()

	var dapp = &keeperMockApp{
		cdc:                   cdc,
		keyPubKeys:            sdk.NewKVStoreKey("pub_keys"),
		keyDeals:              sdk.NewKVStoreKey("deals"),
		keyResponses:          sdk.NewKVStoreKey("responses"),
		keyJustifications:     sdk.NewKVStoreKey("justifications"),
		keyCommits:            sdk.NewKVStoreKey("commits"),
		keyComplaints:         sdk.NewKVStoreKey("complaints"),
		keyReconstructCommits: sdk.NewKVStoreKey("reconstruct_commits"),
	}

	dapp.nsKeeper = randapp.NewKeeper(
		nil,
		dapp.keyPubKeys,
		dapp.keyDeals,
		dapp.keyResponses,
		dapp.keyJustifications,
		dapp.keyCommits,
		dapp.keyComplaints,
		dapp.keyReconstructCommits,
		dapp.cdc,
	)

	return dapp
}
