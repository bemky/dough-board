require 'active_support/encrypted_configuration'

# Allow credentials to be stored in an unencrypted, environment-keyed YAML file
# (config/credentials.yml) rather than the encrypted credentials.yml.enc. When
# the content_path is not a *.enc file it is read verbatim, and the section
# matching the current Rails.env is selected automatically.
module ActiveSupport
  class EncryptedConfiguration
    def read
      fallback = @content_path + "../#{@content_path.basename.to_s.delete_suffix(".enc")}" if @content_path

      if @config_path&.end_with?('.enc')
        super
      elsif @content_path&.exist?
        @content_path.binread
      elsif fallback.exist?
        fallback.binread
      else
        # Allow a config to be started without a file present
        ""
      end
    end

    def config
      return @config if @config

      @config = deserialize(read)
      @config = @config[Rails.env] if @config&.has_key?(Rails.env) && !@config_path&.end_with?('.enc')
      @config = deep_symbolize_keys(@config)
    end

    def dig(*keys)
      config&.dig(*keys)
    end
  end
end
