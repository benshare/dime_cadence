import NonFungibleToken from 0x631e88ae7f1d7c20 // testnet | 0x1d7e57aa55817448 mainnet
import DimeCollectible from 0x056a9cc93a020fad // testnet | 0xa233bed832a43947 mainnet
import FUSD from 0xe223d8a629e49c68 // testnet | 0x3c5959b568896393 mainnet
import FungibleToken from 0x9a0766d93b6608b7 // testnet | 0xf233dcee88fe0abe mainnet

/*
    This contract allows:
    - Anyone to create Sale Offers and place them in their storefront, making it
      publicly accessible.
    - Anyone to accept the offer and buy the item.
    - The Dime admin account to accept offers without transferring tokens
 */

pub contract DimeStorefront {

    // SaleOffer events
    // A sale offer has been created.
    pub event SaleOfferCreated(itemId: UInt64, price: UFix64)
    // Someone has purchased an item that was offered for sale.
    pub event SaleOfferAccepted(itemId: UInt64)
    // A sale offer has been destroyed, with or without being accepted.
    pub event SaleOfferFinished(itemId: UInt64)

    // A sale offer has been removed from the collection of Address.
    pub event SaleOfferRemoved(itemId: UInt64, owner: Address)

    // A sale offer has been inserted into the collection of Address.
    pub event SaleOfferAdded(
      itemId: UInt64,
      creator: Address,
      content: String,
      owner: Address,
      price: UFix64
    )

    pub let verificationKey: [UInt8]
    // Named paths
    pub let StorefrontStoragePath: StoragePath
    pub let StorefrontPublicPath: PublicPath

    // An interface providing a read-only view of a SaleOffer
    pub resource interface SaleOfferPublic {
        pub let itemId: UInt64
        pub let creator: Address
        pub let content: String
        pub let history: [[AnyStruct]]
        
        pub var price: UFix64

        pub fun acceptWithFUSD(payment: @FUSD.Vault,
            buyerCollection: &DimeCollectible.Collection{NonFungibleToken.Receiver},
        )
        pub fun accept(
            buyerCollection: &DimeCollectible.Collection{NonFungibleToken.Receiver}
        )
    }

    // A DimeCollectible NFT being offered to sale for a set fee
    pub resource SaleOffer: SaleOfferPublic {
        // Whether the sale has completed with someone purchasing the item.
        pub var saleCompleted: Bool

        // The NFT for sale.
        pub let itemId: UInt64
        pub let creator: Address
        pub let content: String
        pub let history: [[AnyStruct]]

        // The sale payment price, in dollars
        pub var price: UFix64
        // The vault that will be paid when the item is purchased
        access(self) let receiver: Capability<&FUSD.Vault{FungibleToken.Receiver}>

        // The fraction of the price that goes to Dime
        pub let dimeRoyalty: UFix64
        // The fraction of the price that goes to the original creator
        pub let creatorRoyalty: UFix64

        // The collection containing that Id.
        access(self) let sellerItemProvider: Capability<&DimeCollectible.Collection{NonFungibleToken.Provider}>

        destroy() {
            // Whether the sale completed or not, publicize that it is being withdrawn.
            emit SaleOfferFinished(itemId: self.itemId)
        }

        // Called by a purchaser to accept the sale offer. We only accept payment
        // in FUSD.
        pub fun acceptWithFUSD(payment: @FUSD.Vault,
            buyerCollection: &DimeCollectible.Collection{NonFungibleToken.Receiver},
        ) {
            pre {
                self.saleCompleted == false: "The sale offer has already been accepted"
                payment.balance == self.price: "Payment vault does not contain the required price"
            }

            self.saleCompleted = true

            let nft <- self.sellerItemProvider.borrow()!.withdraw(withdrawID: self.itemId)
            assert(nft.isInstance(DimeCollectible.NFT.getType()), message: "Provided NFT is not of the correct type")
            assert(nft.id == self.itemId, message: "Provided NFT does not have the correct ID")
            let dimeNft <- nft as! @DimeCollectible.NFT
            
            let dimeCut = self.price * self.dimeRoyalty
            let dimePayment <- payment.withdraw(amount: dimeCut)
            let dimeAccount = getAccount(0x631e88ae7f1d7c20)
            let dimeRef = dimeAccount.getCapability(/public/fusdReceiver)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow reference to the Dime admin's vault")
            dimeRef.deposit(from: <- dimePayment)
            
            let creatorCut = self.price * self.creatorRoyalty
            let creatorPayment <- payment.withdraw(amount: creatorCut)
            let creatorAccount = getAccount(dimeNft.creator)
            let creatorRef = creatorAccount.getCapability(/public/fusdReceiver)
                .borrow<&{FungibleToken.Receiver}>()
                ?? panic("Could not borrow reference to the creator's vault")
            creatorRef.deposit(from: <- creatorPayment)

            self.receiver.borrow()!.deposit(from: <- payment)

            dimeNft.addSale(toUser: buyerCollection.owner!.address, atPrice: self.price)
            buyerCollection.deposit(token: <- (dimeNft as! @NonFungibleToken.NFT))

            emit SaleOfferAccepted(itemId: self.itemId)
        }

        // Transfers the token without payment. Requires a key, which is owned by the
        // Dime admin account. The purpose of this is to simulate the exchange of
        // fiat for FUSD. Dime handles the transfer of non-token currency prior to calling
        // this version of accept.
        pub fun accept(
            buyerCollection: &DimeCollectible.Collection{NonFungibleToken.Receiver}
        ) {
            pre {
                self.saleCompleted == false: "The sale offer has already been accepted"
            }

            // We confirm that the caller is the Dime admin by using the Dime public key
            // to verify the provided signature. We'll use the item ID being bought
            // as the agreed-upon plaintext to verify.
            // let key: PublicKey = PublicKey(
            //     publicKey: DimeStorefront.verificationKey,
            //     signatureAlgorithm: SignatureAlgorithm.ECDSA_P256
            // )

            // let isValid = key.verify(signature: signature,
            //     signedData: self.itemId.toString().decodeHex(),
            //     domainSeparationTag: "",
            //     hashAlgorithm: HashAlgorithm.SHA3_256)
            // assert(isValid, message: "Only the Dime admin account can call this version of accept")

            self.saleCompleted = true

            let nft <- self.sellerItemProvider.borrow()!.withdraw(withdrawID: self.itemId)
            // assert(nft.isInstance(DimeCollectible.NFT.getType()), message: nft.getType().identifier.concat(" is not an instance of ").concat(DimeCollectible.NFT.getType().identifier))
            assert(nft.id == self.itemId, message: "Provided NFT does not have the correct ID")
            let dimeNft <- nft as! @DimeCollectible.NFT


            dimeNft.addSale(toUser: buyerCollection.owner!.address, atPrice: self.price)
            buyerCollection.deposit(token: <- (dimeNft as! @NonFungibleToken.NFT))

            emit SaleOfferAccepted(itemId: self.itemId)
        }

        // Take the information required to create a sale offer: the capability
        // to transfer the DimeCollectible NFT and the capability to receive payment
        init(sellerItemProvider: Capability<&DimeCollectible.Collection{NonFungibleToken.Provider}>,
            itemId: UInt64, creator: Address, content: String, price: UFix64, history: [[AnyStruct]], receiver: Capability<&FUSD.Vault{FungibleToken.Receiver}>) {
            pre {
                sellerItemProvider.borrow() != nil: "Cannot borrow collection from seller"
            }

            self.saleCompleted = false

            let collectionRef = sellerItemProvider.borrow()!

            self.sellerItemProvider = sellerItemProvider
            self.itemId = itemId

            self.price = price
            self.creator = creator
            self.content = content
            self.history = history

            self.receiver = receiver
            self.creatorRoyalty = 0.01
            self.dimeRoyalty = 0.01

            emit SaleOfferCreated(itemId: self.itemId, price: self.price)
        }

        pub fun setPrice(newPrice: UFix64) {
            self.price = newPrice
        }
    }

    // An interface for adding and removing SaleOffers to a collection, intended for
    // use by the collection's owner
    pub resource interface StorefrontManager {
        pub fun createSaleOffer(
            sellerItemProvider: Capability<&DimeCollectible.Collection{DimeCollectible.DimeCollectionPublic, NonFungibleToken.Provider}>,
            itemId: UInt64,
            creator: Address,
            content: String,
            price: UFix64,
            history: [[AnyStruct]],
            receiver: Capability<&FUSD.Vault{FungibleToken.Receiver}>
        )
        pub fun removeSaleOffer(itemId: UInt64)
        pub fun changePrice(itemId: UInt64, newPrice: UFix64)
    }

    // An interface to allow listing and borrowing SaleOffers, and purchasing items via SaleOffers in a collection
    pub resource interface StorefrontPublic {
        pub fun getSaleOfferIds(): [UInt64]
        pub fun borrowSaleOffer(itemId: UInt64): &SaleOffer{SaleOfferPublic}?
   }

    // A resource that allows its owner to manage a list of SaleOffers, and purchasers to interact with them
    pub resource Storefront : StorefrontManager, StorefrontPublic {
        access(self) var saleOffers: @{UInt64: SaleOffer}

        // Returns an array of the Ids that are in the collection
        pub fun getSaleOfferIds(): [UInt64] {
            return self.saleOffers.keys
        }

        // Returns an Optional read-only view of the SaleItem for the given itemId if it is contained by this collection.
        // The optional will be nil if the provided itemId is not present in the collection.
        pub fun borrowSaleOffer(itemId: UInt64): &SaleOffer{SaleOfferPublic}? {
            if self.saleOffers[itemId] == nil {
                return nil
            }
            return &self.saleOffers[itemId] as &SaleOffer{SaleOfferPublic}
        }

        // Insert a SaleOffer into the collection, replacing one with the same itemId if present
        pub fun createSaleOffer(
            sellerItemProvider: Capability<&DimeCollectible.Collection{DimeCollectible.DimeCollectionPublic, NonFungibleToken.Provider}>,
            itemId: UInt64,
            creator: Address,
            content: String,
            price: UFix64,
            history: [[AnyStruct]],
            receiver: Capability<&FUSD.Vault{FungibleToken.Receiver}>
        ) {
            let nft = sellerItemProvider.borrow()!.borrowCollectible(id: itemId) ?? panic("Couldn't borrow nft from seller")
            if (!nft.tradeable) {
                panic("Tried to put an untradeable token on sale")
            }
        
            let newOffer <- create SaleOffer(
                sellerItemProvider: sellerItemProvider,
                itemId: itemId,
                creator: creator,
                content: content,
                price: price,
                history: history,
                receiver: receiver
            )

            // Add the new offer to the dictionary, overwriting an old one if it exists
            let oldOffer <- self.saleOffers[itemId] <- newOffer
            destroy oldOffer

            emit SaleOfferAdded(
              itemId: itemId,
              creator: creator,
              content: content,
              owner: self.owner?.address!,
              price: price
            )
        }

        // Remove and return a SaleOffer from the collection
        pub fun removeSaleOffer(itemId: UInt64) {
            let offer <- (self.saleOffers.remove(key: itemId) ?? panic("missing SaleOffer"))
            emit SaleOfferRemoved(itemId: itemId, owner: self.owner?.address!)
            destroy offer
        }

        access(contract) fun push(offer: @SaleOffer) {
            let oldOffer <- self.saleOffers[offer.itemId] <- offer
            destroy oldOffer
        }

        access(contract) fun pop(itemId: UInt64): @SaleOffer? {
            let offer <- self.saleOffers.remove(key: itemId)
            return <- offer
        }

        pub fun changePrice(itemId: UInt64, newPrice: UFix64) {
            pre {
                self.saleOffers[itemId] != nil: "Tried to change price of an item that's not on sale"
            }

            let offer <- self.pop(itemId: itemId)!
            offer.setPrice(newPrice: newPrice)
            self.push(offer: <- offer)
        }

        destroy () {
            destroy self.saleOffers
        }

        init () {
            self.saleOffers <- {}
        }
}

    // Make creating a Storefront publicly accessible.
    pub fun createStorefront(): @Storefront {
        return <-create Storefront()
    }

    init () {
        self.verificationKey = "745f2b97ba96cadc00ff9ac3763c85d675352a35aec9f058403b18c9e8a623f61e657ba2ce5073b9a96076ebfe28d3c8e2e846ae8d53d14c4c5e5bf37794483b".decodeHex()

        self.StorefrontStoragePath = /storage/DimeStorefrontCollection
        self.StorefrontPublicPath = /public/DimeStorefrontCollection
    }
}
 
