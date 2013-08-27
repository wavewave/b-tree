{-# LANGUAGE DeriveGeneric, FlexibleContexts, TemplateHaskell, UndecidableInstances, StandaloneDeriving #-}

module BTree.Types where

import Data.Binary
import GHC.Generics
import Control.Monad (when)
import Control.Applicative
import Control.Lens
import Data.Word
import Data.Int
import qualified Data.ByteString as BS

magic :: Word64
magic = 0xdeadbeefbbbbcccc

-- | An offset within the stream         
type Offset = Int64

-- | The number of entries in a B-tree
type Size = Word64

-- | The maximum number of children of a B-tree inner node
type Order = Word64

-- | 'OnDisk a' is a reference to an object of type 'a' on disk
newtype OnDisk a = OnDisk Offset
                 deriving (Show, Eq, Ord)
                
instance Binary (OnDisk a) where
    get = OnDisk <$> get
    put (OnDisk off) = put off

data BLeaf k e = BLeaf !k !e
               deriving (Generic)
               
deriving instance (Eq k, Eq e) => Eq (BLeaf k e)
deriving instance (Show k, Show e) => Show (BLeaf k e)
    
-- | 'BTree k f e' is a B* tree of key type 'k' with elements of type 'e'.
-- Subtree references are contained within a type 'f'
--
-- The Node constructor contains a left child, and a list of key/child pairs
-- where each child's keys are greater than or equal to the given key.
data BTree k f e = Node (f (BTree k f e)) [(k, f (BTree k f e))]
                 | Leaf (BLeaf k e)
                 deriving (Generic)
     
deriving instance (Show e, Show k, Show (f (BTree k f e))) => Show (BTree k f e)
deriving instance (Eq e, Eq k, Eq (f (BTree k f e))) => Eq (BTree k f e)

instance (Binary k, Binary (f (BTree k f e)), Binary e)
  => Binary (BTree k f e) where
    get = do typ <- getWord8
             case typ of
               0 -> Node <$> get <*> get
               1 -> bleaf <$> get <*> get
               _ -> fail "BTree.Types/get: Unknown node type"
      where bleaf k v = Leaf (BLeaf k v)
    put (Node e0 es)         = putWord8 0 >> put e0 >> put es
    put (Leaf (BLeaf k0 e))  = putWord8 1 >> put k0 >> put e
    
treeStartKey :: BTree k f e -> k
treeStartKey (Node _ ((k,_):_)) = k
treeStartKey (Node _ [])        = error "BTree.Types.treeStartKey: Empty node"
treeStartKey (Leaf (BLeaf k _)) = k

-- | B-tree file header
data BTreeHeader k e = BTreeHeader { _btMagic   :: !Word64
                                   , _btVersion :: !Word64
                                   , _btOrder   :: !Order
                                   , _btSize    :: !Size
                                   , _btRoot    :: !(OnDisk (BTree k OnDisk e))
                                   }
                 deriving (Show, Eq, Generic)
makeLenses ''BTreeHeader     

instance Binary (BTreeHeader k e)

validateHeader :: BTreeHeader k e -> Either String ()
validateHeader hdr = do
    when (hdr^.btMagic /= magic) $ Left "Invalid magic number"
    when (hdr^.btVersion > 1) $ Left "Invalid version"
    
data LookupTree k e = LookupTree { _ltData    :: !BS.ByteString
                                 , _ltHeader  :: !(BTreeHeader k e)
                                 }
makeLenses ''LookupTree
