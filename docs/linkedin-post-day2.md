# LinkedIn Post — Day 2 (Project reveal)

**Building an ERP-style data migration from first principles**

I spent the last few weeks building a SQL-first data migration lab — the kind of pipeline that sits behind every "we're consolidating two ERPs after the merger" project.

The premise is simple: take two messy, overlapping source systems (a Northwind ERP and a CRM-style CSV export with the same customers/vendors but different formatting, generated names, and net-new records), and produce one clean, deduplicated target — with full traceability for every decision.

What I wanted to internalize wasn't ETL syntax. It was the **methodology** that separates a migration that lands cleanly from one that quietly corrupts the target system.

𝗙𝗶𝘃𝗲 𝗽𝗿𝗶𝗻𝗰𝗶𝗽𝗹𝗲𝘀 𝘁𝗵𝗲 𝗹𝗮𝗯 𝗶𝗺𝗽𝗹𝗲𝗺𝗲𝗻𝘁𝘀 𝗲𝗻𝗱-𝘁𝗼-𝗲𝗻𝗱:

𝟭. 𝗦𝗻𝗮𝗽𝘀𝗵𝗼𝘁𝘀, 𝗻𝗼𝘁 𝗹𝗶𝘃𝗲 𝗾𝘂𝗲𝗿𝗶𝗲𝘀.
Every source is copied into a point-in-time snapshot before transformation. Sources are never joined directly — every match happens in the working layer.

𝟮. 𝗖𝗮𝗻𝗼𝗻𝗶𝗰𝗮𝗹 𝗺𝗼𝗱𝗲𝗹 𝘄𝗶𝘁𝗵 𝗯𝗶𝗱𝗶𝗿𝗲𝗰𝘁𝗶𝗼𝗻𝗮𝗹 𝗻𝗮𝗺𝗲 𝗵𝗮𝗻𝗱𝗹𝗶𝗻𝗴.
Northwind stores `ContactName` as a single string. The CSV stores First/Middle/Last separately. The working layer splits one and rebuilds the other so both sources speak the same shape.

𝟯. 𝗠𝘂𝗹𝘁𝗶-𝘀𝘁𝗿𝗮𝘁𝗲𝗴𝘆 𝗺𝗮𝘁𝗰𝗵𝗶𝗻𝗴.
Email → Phone → Name+City → Company+City. Each strategy creates its own match group with the rule that produced it logged.

𝟰. 𝗗𝗲𝘁𝗲𝗿𝗺𝗶𝗻𝗶𝘀𝘁𝗶𝗰 𝘀𝘂𝗿𝘃𝗶𝘃𝗼𝗿𝘀𝗵𝗶𝗽 𝘄𝗶𝘁𝗵 𝗮 𝗿𝗲𝗮𝘀𝗼𝗻 𝗰𝗼𝗱𝗲.
When duplicates collapse, the "winner" is the record ranked by data completeness, and the reason ("Complete data: email+phone+address") is stored alongside the surviving record. No invisible decisions.

𝟱. 𝗥𝗲𝗰𝗼𝗻𝗰𝗶𝗹𝗶𝗮𝘁𝗶𝗼𝗻 𝗮𝘀 𝗮 𝗳𝗶𝗿𝘀𝘁-𝗰𝗹𝗮𝘀𝘀 𝗼𝘂𝘁𝗽𝘂𝘁.
Reporting views show source-to-target row counts per system, duplicate resolution detail, data quality by stage, and source lineage on every target record.

𝗪𝗵𝗮𝘁 𝗜 𝗱𝗲𝗹𝗶𝗯𝗲𝗿𝗮𝘁𝗲𝗹𝘆 𝗱𝗶𝗱 𝗻𝗼𝘁 𝗯𝘂𝗶𝗹𝗱:
Transitive match clustering, per-attribute survivorship, incremental reruns, partitioning. Those are listed in the repo's known-limitations doc — being precise about the gap between "lab" and "production" is itself the lesson.

𝗪𝗵𝘆 𝗦𝗤𝗟-𝗳𝗶𝗿𝘀𝘁:
Business users can read every transformation. Set-based logic scales further than row-by-row. And any SQL Server shop can run it without a vendor account.

Repo + reconciliation screenshots in the comments. Tomorrow I'll share the same pipeline rebuilt for Microsoft Fabric — same methodology, different stack.

---

## Drafting notes (not part of the post)

- Cut the "junior engineers think the hard part is ETL" line — it reads as condescending.
- Replaced "I've analyzed several enterprise migration platforms" with "I wanted to internalize the methodology" — honest, no inflated authority.
- Explicitly named the known-limitations doc inside the post. Counter-intuitively, this makes you sound *more* senior, not less.
- Saved the Fabric tease for the closing line so Day 3 has a built-in hook.
- 𝗯𝗼𝗹𝗱 unicode used for section headers — LinkedIn doesn't render markdown, so this is the standard trick.

## Suggested first comment (drop the link there, not in the post body)

```
Repo: <github-url>
Known limitations doc: <github-url>/blob/main/docs/05-known-limitations.md
```
