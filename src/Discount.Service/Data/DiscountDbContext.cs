using System.Data.Entity;
using eShop.Contracts.Data;
using eShop.Contracts.Models;

namespace Discount.Service.Data
{
    public class DiscountDbContext : DbContext
    {
        public DiscountDbContext() : base(SqlServerConnectionString.FromConfiguration("DiscountDb"))
        {
            Database.ExecuteSqlCommand(@"
                IF OBJECT_ID(N'dbo.DiscountItems', N'U') IS NULL
                    CREATE TABLE dbo.DiscountItems (
                        Id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
                        Size FLOAT NOT NULL,
                        Start DATETIME NOT NULL,
                        [End] DATETIME NOT NULL
                    )");
        }

        public DbSet<DiscountItem> DiscountItems { get; set; }

        protected override void OnModelCreating(DbModelBuilder modelBuilder)
        {
            modelBuilder.Entity<DiscountItem>().ToTable("DiscountItems");
        }
    }
}
