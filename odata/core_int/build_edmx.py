"""Generate odata/ZCTD_CORE_INT.edmx (OData V2 model of ZCTD_CORE_INT_SRV).

    python odata/core_int/build_edmx.py

Add a new integration object: append its entity (and association) to
ENTITIES / ASSOCIATIONS, regenerate, then run ZCTD_FM_SEGW_UPDATE with the
TR and redefine the new *_GET_ENTITY(SET) / CREATE methods in DPC_EXT.
Property names in upper case must equal the DDIC structure field names.
"""
from xml.sax.saxutils import escape

NS = 'ZCTD_CORE_INT_SRV'


def s(name, length, label, key=False):
    return ('String', name, length, label, key)


def d(name, prec, scale, label):
    return ('Decimal', name, (prec, scale), label, False)


def i(name, label):
    return ('Int32', name, None, label, False)


ENTITIES = {
    # name: (entity set, creatable, properties)
    'Vendor': ('VendorSet', True, [
        s('Supplier', 10, 'Supplier', True), s('BusinessPartner', 10, 'Business Partner'),
        s('BPGrouping', 4, 'BP Grouping'), s('AccountGroup', 4, 'Account Group'),
        s('Name1', 40, 'Name'), s('Name2', 40, 'Name 2'), s('SearchTerm', 20, 'Search Term'),
        s('Street', 60, 'Street'), s('City', 40, 'City'), s('PostalCode', 10, 'Postal Code'),
        s('Region', 3, 'Region'), s('Country', 3, 'Country'), s('Language', 2, 'Language'),
        s('Telephone', 30, 'Telephone'), s('Email', 241, 'E-Mail'), s('TaxNumber1', 16, 'Tax Number 1'),
        s('VATNumber', 20, 'VAT Number'), s('PostingBlock', 1, 'Central Posting Block'),
        s('PurchasingBlock', 1, 'Central Purchasing Block'), s('DeletionFlag', 1, 'Deletion Flag'),
        s('CreatedOn', 8, 'Created On'), s('CreatedBy', 12, 'Created By')]),
    'PurchaseReq': ('PurchaseReqSet', False, [
        s('PRNumber', 10, 'Purchase Requisition', True), s('PRType', 4, 'PR Type'),
        s('CreatedBy', 12, 'Created By'), s('CreatedOn', 8, 'Created On'), s('RequestDate', 8, 'Request Date'),
        s('Requisitioner', 12, 'Requisitioner'), s('TrackingNo', 10, 'Tracking Number'),
        s('ReleaseStrategy', 2, 'Release Strategy'), s('ReleaseIndicator', 1, 'Release Indicator'),
        i('ItemCount', 'Number of Items'), d('TotalValue', 23, 2, 'Total Value'), s('Currency', 5, 'Currency')]),
    'PurchaseReqItem': ('PurchaseReqItemSet', False, [
        s('PRNumber', 10, 'Purchase Requisition', True), s('Item', 5, 'Item', True),
        s('Material', 40, 'Material'), s('ShortText', 40, 'Short Text'), s('MaterialGroup', 9, 'Material Group'),
        s('Plant', 4, 'Plant'), s('StorageLocation', 4, 'Storage Location'), d('Quantity', 13, 3, 'Quantity'),
        s('UOM', 3, 'Unit'), s('DeliveryDate', 8, 'Delivery Date'), d('ValuationPrice', 23, 2, 'Valuation Price'),
        d('PriceUnit', 5, 0, 'Price Unit'), s('Currency', 5, 'Currency'), d('ItemValue', 23, 2, 'Item Value'),
        s('PurchasingGroup', 3, 'Purchasing Group'), s('PurchasingOrg', 4, 'Purchasing Org.'),
        s('AcctAssignCategory', 1, 'Acct Assignment Cat.'), s('ItemCategory', 1, 'Item Category'),
        s('WBSElement', 24, 'WBS Element'), s('ReleaseIndicator', 1, 'Release Indicator'),
        s('ProcessingStatus', 1, 'Processing Status'), s('DeletionIndicator', 1, 'Deletion Indicator'),
        s('Closed', 1, 'Closed'), s('PONumber', 10, 'PO Number'), s('POItem', 5, 'PO Item'),
        s('Requisitioner', 12, 'Requisitioner'), s('TrackingNo', 10, 'Tracking Number')]),
}

# (association, from entity, nav property, to entity, key property)
ASSOCIATIONS = [('PurchaseReqToItems', 'PurchaseReq', 'Items', 'PurchaseReqItem', 'PRNumber')]


def prop(p):
    kind, name, size, label, key = p
    attrs = f'Name="{name}" Type="Edm.{kind}" Nullable="{"false" if key else "true"}"'
    if kind == 'String':
        attrs += f' MaxLength="{size}"'
    elif kind == 'Decimal':
        attrs += f' Precision="{size[0]}" Scale="{size[1]}"'
    return f'        <Property {attrs} sap:unicode="false" sap:label="{escape(label)}"/>'


out = ['<?xml version="1.0" encoding="utf-8"?>',
       '<edmx:Edmx Version="1.0" xmlns:edmx="http://schemas.microsoft.com/ado/2007/06/edmx" '
       'xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" '
       'xmlns:sap="http://www.sap.com/Protocols/SAPData">',
       '  <edmx:DataServices m:DataServiceVersion="2.0">',
       f'    <Schema Namespace="{NS}" xml:lang="en" sap:schema-version="1" '
       'xmlns="http://schemas.microsoft.com/ado/2008/09/edm">']
for name, (_, _, props) in ENTITIES.items():
    out.append(f'      <EntityType Name="{name}" sap:content-version="1">')
    out.append('        <Key>')
    out += [f'          <PropertyRef Name="{p[1]}"/>' for p in props if p[4]]
    out.append('        </Key>')
    out += [prop(p) for p in props]
    for assoc, frm, nav, to, _ in ASSOCIATIONS:
        if frm == name:
            out.append(f'        <NavigationProperty Name="{nav}" Relationship="{NS}.{assoc}" '
                       f'FromRole="FromRole_{assoc}" ToRole="ToRole_{assoc}"/>')
    out.append('      </EntityType>')
for assoc, frm, nav, to, key in ASSOCIATIONS:
    out += [f'      <Association Name="{assoc}" sap:content-version="1">',
            f'        <End Type="{NS}.{frm}" Multiplicity="1" Role="FromRole_{assoc}"/>',
            f'        <End Type="{NS}.{to}" Multiplicity="*" Role="ToRole_{assoc}"/>',
            '        <ReferentialConstraint>',
            f'          <Principal Role="FromRole_{assoc}"><PropertyRef Name="{key}"/></Principal>',
            f'          <Dependent Role="ToRole_{assoc}"><PropertyRef Name="{key}"/></Dependent>',
            '        </ReferentialConstraint>',
            '      </Association>']
out.append(f'      <EntityContainer Name="{NS}_Entities" m:IsDefaultEntityContainer="true" sap:supported-formats="atom json xlsx">')
for name, (eset, creatable, _) in ENTITIES.items():
    c = 'true' if creatable else 'false'
    out.append(f'        <EntitySet Name="{eset}" EntityType="{NS}.{name}" sap:creatable="{c}" sap:updatable="false" '
               f'sap:deletable="false" sap:pageable="true" sap:content-version="1"/>')
for assoc, frm, nav, to, _ in ASSOCIATIONS:
    fs, ts = ENTITIES[frm][0], ENTITIES[to][0]
    out += [f'        <AssociationSet Name="{assoc}Set" Association="{NS}.{assoc}" sap:creatable="false" '
            'sap:updatable="false" sap:deletable="false" sap:content-version="1">',
            f'          <End EntitySet="{fs}" Role="FromRole_{assoc}"/>',
            f'          <End EntitySet="{ts}" Role="ToRole_{assoc}"/>',
            '        </AssociationSet>']
out += ['      </EntityContainer>', '    </Schema>', '  </edmx:DataServices>', '</edmx:Edmx>']
open('D:/MCP_SAP_PRIVATE/MCP_SAP_PRIVATE/odata/ZCTD_CORE_INT.edmx', 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('written', len(out), 'lines')
