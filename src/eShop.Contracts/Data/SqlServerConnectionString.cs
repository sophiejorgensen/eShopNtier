using System;
using System.Configuration;
using System.Data.SqlClient;

namespace eShop.Contracts.Data
{
    public static class SqlServerConnectionString
    {
        public static string FromConfiguration(string name)
        {
            var configured = ConfigurationManager.ConnectionStrings[name];
            if (configured == null)
                throw new InvalidOperationException("Connection string '" + name + "' is not configured.");

            var password = Environment.GetEnvironmentVariable("ESHOP_SQL_PASSWORD");
            if (string.IsNullOrWhiteSpace(password))
                throw new InvalidOperationException("Set the ESHOP_SQL_PASSWORD environment variable before starting the application.");

            var builder = new SqlConnectionStringBuilder(configured.ConnectionString);
            var server = Environment.GetEnvironmentVariable("ESHOP_SQL_SERVER");
            if (!string.IsNullOrWhiteSpace(server))
                builder.DataSource = server;

            var user = Environment.GetEnvironmentVariable("ESHOP_SQL_USER");
            if (!string.IsNullOrWhiteSpace(user))
                builder.UserID = user;

            builder.Password = password;
            return builder.ConnectionString;
        }
    }
}
