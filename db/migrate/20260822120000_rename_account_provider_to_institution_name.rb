class RenameAccountProviderToInstitutionName < ActiveRecord::Migration[8.1]
  def change
    rename_column :accounts, :provider, :institution_name
  end
end
