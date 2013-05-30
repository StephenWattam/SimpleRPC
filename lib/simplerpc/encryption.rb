
require 'openssl'

module SimpleRPC

  # Handles openssl-based encryption of authentication details
  #
  # The auth system used is not terribly secure, but will guard against
  # casual attackers.  If you are particularly concerned, turn it off and
  # use SSH tunnels.
  #
  module Encryption

    # How strong to make the AES encryption
    CIPHER_STRENGTH = 256

    # Encrypt data
    def self.encrypt(password, secret, salt)
        # Encrypt with salted key
        cipher         = OpenSSL::Cipher::AES.new(CIPHER_STRENGTH, :CBC)
        cipher.encrypt
        cipher.key     = salt_key(salt, secret)
        return cipher.update(password) + cipher.final
    rescue StandardError
      return nil  # Don't allow anyone to deliberately cause lockups
    end

    # Decrypt data
    def self.decrypt(raw, secret, salt)
        # Decrypt raw input
        decipher      = OpenSSL::Cipher::AES.new(CIPHER_STRENGTH, :CBC)
        decipher.decrypt
        decipher.key  = salt_key(salt, secret)
        return decipher.update(raw) + decipher.final
    rescue StandardError
      return nil  # Don't allow anyone to deliberately cause lockups
    end

    # Salt a key by simply adding the two
    # together
    def self.salt_key(salt, key)
      return salt + key
    end

  end
end
