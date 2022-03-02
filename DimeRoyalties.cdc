/* SPDX-License-Identifier: UNLICENSED */

import DimeCollectibleV3 from 0xf5cdaace879e5a79
import FungibleToken from 0xf233dcee88fe0abe
import FUSD from 0x3c5959b568896393
import NonFungibleToken from 0x1d7e57aa55817448

pub contract DimeRoyalties {
    pub let ReleasesStoragePath: StoragePath
    pub let ReleasesPublicPath: PublicPath

	pub struct SaleShares {
		access(self) let recipients: {Address: DimeCollectibleV3.Recipient}

		init(recipients: {Address: DimeCollectibleV3.Recipient}) {
			var total = 0.0
			for recipient in recipients.values {
				total = total + recipient.allotment
			}
			assert(total == 1.0, message: "Total sale shares must equal exactly 1")
			self.recipients = recipients
		}

		pub fun getRecipients(): {Address: DimeCollectibleV3.Recipient} {
			return self.recipients
		}
	}

    pub resource interface ReleasePublic {
        pub let totalRoyalties: UFix64
        pub fun getRoyaltyIds(): [UInt64]
        pub fun getRoyaltyOwners(): [Capability<&FUSD.Vault{FungibleToken.Receiver}>?]
        pub fun getReleaseIds(): [UInt64]
        pub fun getSaleShares(): SaleShares
    }

    pub resource Release: ReleasePublic {
        pub let id: UInt64

        pub let totalRoyalties: UFix64

        // Map from each royalty NFT ID to the current owner's vault for payment.
        // When a royalty NFT is purchase, the stored vault is updated to the new owner's
        access(self) let royaltyNFTs: {UInt64: Capability<&FUSD.Vault{FungibleToken.Receiver}>?}
        pub fun getRoyaltyIds(): [UInt64] {
            return self.royaltyNFTs.keys
        }
        pub fun getRoyaltyOwners(): [Capability<&FUSD.Vault{FungibleToken.Receiver}>?] {
            return self.royaltyNFTs.values
        }
        pub fun addRoyaltyNFT(id: UInt64) {
            self.royaltyNFTs[id] = nil
        }
        pub fun removeRoyaltyNFT(id: UInt64) {
            self.royaltyNFTs.remove(key: id)
        }

        // A list of the associated release NFTs
        access(self) let releaseNFTs: [UInt64]
        pub fun getReleaseIds(): [UInt64] {
            return self.releaseNFTs
        }
        pub fun addReleaseNFT(id: UInt64) {
            self.releaseNFTs.append(id)
        }
        pub fun removeReleaseNFT(id: UInt64) {
            self.releaseNFTs.remove(at: id)
        }

        // How the proceeds from sales of this release will be divided
        access(self) var saleShares: SaleShares
        pub fun getSaleShares(): SaleShares {
			return self.saleShares
		}
		pub fun setSaleShares(newShares: SaleShares) {
			self.saleShares = newShares
		}

        pub init(id: UInt64, totalRoyalties: UFix64, royaltyIds: [UInt64],
            saleShares: SaleShares) {
            self.id = id
            self.totalRoyalties = totalRoyalties
            let royalties: {UInt64: Capability<&FUSD.Vault{FungibleToken.Receiver}>?} = {}
            for royaltyId in royaltyIds {
                royalties[royaltyId] = nil
            }
            self.royaltyNFTs = royalties
            self.releaseNFTs = []
            self.saleShares = saleShares
        }
    }

    pub resource interface ReleaseCollectionPublic {
        pub fun getReleaseIds(): [UInt64]
        pub fun borrowPublicRelease(id: UInt64): &Release{ReleasePublic}
    }

    pub resource ReleaseCollection: ReleaseCollectionPublic {
        pub let releases: @{UInt64: Release}
        pub var nextReleaseId: UInt64

        init() {
            self.releases <- {}
            self.nextReleaseId = 0
        }
        
        destroy () {
			destroy self.releases
		}

        pub fun getReleaseIds(): [UInt64] {
            return self.releases.keys
        }

        pub fun borrowPublicRelease(id: UInt64): &Release{ReleasePublic} {
            return &(self.releases[id]) as &Release{ReleasePublic}
        }

        pub fun borrowPrivateRelease(id: UInt64): &Release {
            return &(self.releases[id]) as &Release
        }

        pub fun createRelease(collection: &{NonFungibleToken.CollectionPublic}, tokenIds: [UInt64],
            totalRoyalties: UFix64, creators: [Address], royaltyContent: String, tradeable: Bool,
            saleShares: SaleShares) {

            let release <- create Release(id: self.nextReleaseId, totalRoyalties: totalRoyalties,
                royaltyIds: tokenIds, saleShares: saleShares)
            let existing <- self.releases[self.nextReleaseId] <- release
            // This should always be null, but we need to handle this explicitly
            destroy existing
            self.nextReleaseId = self.nextReleaseId + (1 as UInt64)

            let minterAddress: Address = 0x056a9cc93a020fad // 0x056a9cc93a020fad for testnet. 0xf5cdaace879e5a79 for mainnet
            let minterRef = getAccount(minterAddress)
                .getCapability<&DimeCollectibleV3.NFTMinter>(DimeCollectibleV3.MinterPublicPath)
                .borrow()!

            let releaseReference = &(self.releases[self.nextReleaseId]) as &Release{ReleasePublic}
            minterRef.mintRoyaltyNFTs(collection: collection, tokenIds: tokenIds,
                creators: creators, content: royaltyContent, tradeable: tradeable)
        }
    }

    pub fun createReleaseCollection(): @ReleaseCollection {
        return <- create ReleaseCollection()
    }

	init () {
		self.ReleasesStoragePath = /storage/Releases
		self.ReleasesPublicPath = /public/Releases
	}
}