-- |
-- Module      : Crypto.Saltine.Core.SecretBox
-- Copyright   : (c) Joseph Abrahamson 2013
-- License     : MIT
-- 
-- Maintainer  : me@jspha.com
-- Stability   : experimental
-- Portability : non-portable
-- 
-- Secret-key authenticated encryption:
-- "Crypto.Saltine.Core.SecretBox"
-- 
-- The 'secretbox' function encrypts and authenticates a message
-- 'ByteString' using a secret key and a nonce. The 'secretboxOpen'
-- function verifies and decrypts a ciphertext 'ByteString' using a
-- secret key and a nonce. If the ciphertext fails validation,
-- 'secretboxOpen' returns 'Nothing'.
-- 
-- The "Crypto.Saltine.Core.SecretBox" module is designed to meet
-- the standard notions of privacy and authenticity for a secret-key
-- authenticated-encryption scheme using nonces. For formal
-- definitions see, e.g., Bellare and Namprempre, "Authenticated
-- encryption: relations among notions and analysis of the generic
-- composition paradigm," Lecture Notes in Computer Science 1976
-- (2000), 531–545, <http://www-cse.ucsd.edu/~mihir/papers/oem.html>.
-- 
-- Note that the length is not hidden. Note also that it is the
-- caller's responsibility to ensure the uniqueness of nonces—for
-- example, by using nonce 1 for the first message, nonce 2 for the
-- second message, etc. Nonces are long enough that randomly generated
-- nonces have negligible risk of collision.
-- 
-- "Crypto.Saltine.Core.SecretBox" is
-- @crypto_secretbox_xsalsa20poly1305@, a particular combination of
-- Salsa20 and Poly1305 specified in \"Cryptography in NaCl\"
-- (<http://nacl.cr.yp.to/valid.html>). This function is conjectured
-- to meet the standard notions of privacy and authenticity.
-- 
-- This is version 2010.08.30 of the secretbox.html web page.
module Crypto.Saltine.Core.SecretBox (
  Key, Nonce,
  secretbox, secretboxOpen,
  newKey, newNonce
  ) where

import Crypto.Saltine.Class
import Crypto.Saltine.Internal.Util
import qualified Crypto.Saltine.Internal.ByteSizes as Bytes

import Foreign.C
import Foreign.Ptr
import qualified Data.ByteString as S
import           Data.ByteString (ByteString)

import Control.Applicative

-- $types

-- | An opaque 'secretbox' cryptographic key.
newtype Key = Key ByteString deriving (Eq, Ord)

instance IsEncoding Key where
  decode v = case S.length v == Bytes.secretBoxKey of
    True -> Just (Key v)
    False -> Nothing
  {-# INLINE decode #-}
  encode (Key v) = v
  {-# INLINE encode #-}

-- | An opaque 'secretbox' nonce.
newtype Nonce = Nonce ByteString deriving (Eq, Ord)

instance IsEncoding Nonce where
  decode v = case S.length v == Bytes.secretBoxNonce of
    True -> Just (Nonce v)
    False -> Nothing
  {-# INLINE decode #-}
  encode (Nonce v) = v
  {-# INLINE encode #-}

instance IsNonce Nonce where
  zero = Nonce (S.replicate Bytes.secretBoxNonce 0)
  nudge (Nonce n) = Nonce (nudgeBS n)

-- | Creates a random key of the correct size for 'secretbox'.
newKey :: IO Key
newKey = Key <$> randomVector Bytes.secretBoxKey

-- | Creates a random nonce of the correct size for 'secretbox'.
newNonce :: IO Nonce
newNonce = Nonce <$> randomVector Bytes.secretBoxNonce

-- | Encrypts a message. It is infeasible for an attacker to decrypt
-- the message so long as the 'Nonce' is never repeated.
secretbox :: Key -> Nonce
             -> ByteString
             -- ^ Message
             -> ByteString
             -- ^ Ciphertext
secretbox (Key key) (Nonce nonce) msg =
  unpad' . snd . buildUnsafeCVector len $ \pc ->
    constVectors [key, pad' msg, nonce] $ \
      [(pk, _), (pm, _), (pn, _)] ->
      c_secretbox pc pm (fromIntegral len) pn pk
  where len    = S.length msg + Bytes.secretBoxZero
        pad'   = pad Bytes.secretBoxZero
        unpad' = unpad Bytes.secretBoxBoxZero

-- | Decrypts a message. Returns 'Nothing' if the keys and message do
-- not match.
secretboxOpen :: Key -> Nonce 
                 -> ByteString
                 -- ^ Ciphertext
                 -> Maybe ByteString
                 -- ^ Message
secretboxOpen (Key key) (Nonce nonce) cipher =
  let (err, vec) = buildUnsafeCVector len $ \pm ->
        constVectors [key, pad' cipher, nonce] $ \
          [(pk, _), (pc, _), (pn, _)] ->
          c_secretbox_open pm pc (fromIntegral len) pn pk
  in hush . handleErrno err $ unpad' vec
  where len    = S.length cipher + Bytes.secretBoxBoxZero
        pad'   = pad Bytes.secretBoxBoxZero
        unpad' = unpad Bytes.secretBoxZero

-- | The secretbox C API uses 0-padded C strings. Always returns 0.
foreign import ccall "crypto_secretbox"
  c_secretbox :: Ptr CChar
                 -- ^ Cipher 0-padded output buffer
                 -> Ptr CChar
                 -- ^ Constant 0-padded message input buffer
                 -> CULLong
                 -- ^ Length of message input buffer (incl. 0s)
                 -> Ptr CChar
                 -- ^ Constant nonce buffer
                 -> Ptr CChar
                 -- ^ Constant key buffer
                 -> IO CInt

-- | The secretbox C API uses 0-padded C strings. Returns 0 if
-- successful or -1 if verification failed.
foreign import ccall "crypto_secretbox_open"
  c_secretbox_open :: Ptr CChar
                      -- ^ Message 0-padded output buffer
                      -> Ptr CChar
                      -- ^ Constant 0-padded message input buffer
                      -> CULLong
                      -- ^ Length of message input buffer (incl. 0s)
                      -> Ptr CChar
                      -- ^ Constant nonce buffer
                      -> Ptr CChar
                      -- ^ Constant key buffer
                      -> IO CInt