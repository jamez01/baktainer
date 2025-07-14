# frozen_string_literal: true

# sqlite backup command generator
class Baktainer::BackupCommand
  def sqlite(database:, login: nil, password: nil)
    {
      env: [],
      cmd: ['sqlite3', database, '.dump']
    }
  end
end
